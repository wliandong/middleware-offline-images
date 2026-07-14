#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

REMOTE_PATH=/tmp/middleware-probe-images.sh
REMOTE_SCRIPT="$(cat <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

STACK_ROOT='__REMOTE_STACK_ROOT__'
IMAGE_PLATFORM='linux/amd64'
MIRROR_PREFIXES='__MIRROR_PREFIXES__'
MYSQL_IMAGE='__MYSQL_IMAGE__'
REDIS_IMAGE='__REDIS_IMAGE__'
MONGODB_IMAGE='__MONGODB_IMAGE__'
KAFKA_IMAGE='__KAFKA_IMAGE__'

manifest_has_platform() {
  tr '\n' ' ' | grep -Eq '"platform"[[:space:]]*:[[:space:]]*\{[^}]*"architecture"[[:space:]]*:[[:space:]]*"amd64"[^}]*"os"[[:space:]]*:[[:space:]]*"linux"'
}

manifest_digest() {
  sed -n '/"digest"[[:space:]]*:/ { s/.*"digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/; p; q; }'
}

for prefix in $MIRROR_PREFIXES; do
  workdir="$(mktemp -d /tmp/middleware-manifests.XXXXXX)"
  trap 'rm -rf "$workdir"' EXIT
  manifest_file="$workdir/image-manifests.txt"
  env_file="$workdir/resolved-images.env"
  accepted=1

  for key in MYSQL REDIS MONGODB KAFKA; do
    image_var="${key}_IMAGE"
    image="${!image_var}"
    reference="${prefix}/${image}"
    if ! manifest="$(docker manifest inspect --verbose "$reference" 2>&1)"; then
      printf 'Mirror %s cannot inspect %s.\n' "$prefix" "$reference" >&2
      accepted=0
      break
    fi
    if ! manifest_has_platform <<<"$manifest"; then
      printf 'Mirror %s lacks %s for %s.\n' "$prefix" "$IMAGE_PLATFORM" "$reference" >&2
      accepted=0
      break
    fi
    digest="$(manifest_digest <<<"$manifest")"
    if [[ ! "$digest" =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
      printf 'Mirror %s returned no content digest for %s.\n' "$prefix" "$reference" >&2
      accepted=0
      break
    fi
    printf '%s\t%s\t%s\n' "$key" "$reference" "$digest" >>"$manifest_file"
    printf '%s_IMAGE_REF=%s@%s\n' "$key" "$reference" "$digest" >>"$env_file"
  done

  if (( accepted )); then
    install -d -m 0755 "$STACK_ROOT/reports"
    install -m 0644 "$manifest_file" "$STACK_ROOT/reports/image-manifests.txt"
    install -m 0644 "$env_file" "$STACK_ROOT/resolved-images.env"
    printf 'Resolved all images through mirror %s.\n' "$prefix"
    exit 0
  fi

  rm -rf "$workdir"
  trap - EXIT
done

printf 'No configured mirror provides all required linux/amd64 images.\n' >&2
exit 1
REMOTE_SCRIPT
)"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REMOTE_STACK_ROOT__/$REMOTE_STACK_ROOT}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__MIRROR_PREFIXES__/$MIRROR_PREFIXES}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__MYSQL_IMAGE__/$MYSQL_IMAGE}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REDIS_IMAGE__/$REDIS_IMAGE}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__MONGODB_IMAGE__/$MONGODB_IMAGE}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__KAFKA_IMAGE__/$KAFKA_IMAGE}"

if [[ "${PRINT_REMOTE_SCRIPT:-0}" == "1" ]]; then
  printf '%s\n' "$REMOTE_SCRIPT"
  exit 0
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY RUN: upload manifest probe payload to %s:%s.\n' "$REMOTE_HOST" "$REMOTE_PATH"
  printf 'DRY RUN: inspect all exact image tags with docker manifest inspect --verbose for linux/amd64.\n'
  printf 'DRY RUN: write accepted references and digests to %s/resolved-images.env and %s/reports/image-manifests.txt.\n' "$REMOTE_STACK_ROOT" "$REMOTE_STACK_ROOT"
  printf '%s\n' "$REMOTE_SCRIPT"
  exit 0
fi

payload="$(mktemp "${TMPDIR:-/tmp}/middleware-probe-images.XXXXXX")"
trap 'rm -f "$payload"' EXIT
printf '%s\n' "$REMOTE_SCRIPT" >"$payload"
run scp -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$payload" "$REMOTE_HOST:$REMOTE_PATH"
remote "bash $REMOTE_PATH"
