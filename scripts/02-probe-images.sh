#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

REMOTE_PATH=/tmp/middleware-probe-images.sh
REMOTE_PARSER_PATH=/tmp/middleware-select-manifest-digest.py
PARSER="$ROOT/scripts/lib/manifest-select.py"

python_command() {
  command -v python >/dev/null 2>&1 && { printf '%s\n' python; return; }
  command -v python3 >/dev/null 2>&1 && { printf '%s\n' python3; return; }
  printf 'Python is required for manifest selection.\n' >&2
  exit 1
}

if [[ "${1:-}" == "--select-manifest-digest" ]]; then
  test "${2:-}" != ""
  exec "$(python_command)" "$PARSER" "$2" "$IMAGE_PLATFORM"
fi

REMOTE_SCRIPT="$(cat <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

STACK_ROOT='__REMOTE_STACK_ROOT__'
IMAGE_PLATFORM='linux/amd64'
MANIFEST_PARSER='/tmp/middleware-select-manifest-digest.py'
MIRROR_PREFIXES='__MIRROR_PREFIXES__'
MYSQL_IMAGE='__MYSQL_IMAGE__'
REDIS_IMAGE='__REDIS_IMAGE__'
MONGODB_IMAGE='__MONGODB_IMAGE__'
KAFKA_IMAGE='__KAFKA_IMAGE__'

RESOLUTION_ROOT="$STACK_ROOT/image-resolution"
CURRENT_LINK="$RESOLUTION_ROOT/current"
stage_dir=
release_dir=
published=0

cleanup() {
  local status=$?
  [[ -z "$stage_dir" ]] || rm -rf "$stage_dir"
  if (( ! published )) && [[ -n "$release_dir" ]]; then
    rm -f "$release_dir/commit"
    rm -rf "$release_dir"
  fi
  exit "$status"
}

publish_link() {
  local target="$1"
  local destination="$2"
  local temporary="$destination.tmp.$$"
  rm -f "$temporary"
  ln -s "$target" "$temporary"
  mv -f "$temporary" "$destination"
}

install -d -m 0755 "$RESOLUTION_ROOT" "$STACK_ROOT/reports"
trap cleanup EXIT
for prefix in $MIRROR_PREFIXES; do
  stage_dir="$(mktemp -d "$RESOLUTION_ROOT/.staging.XXXXXX")"
  manifest_file="$stage_dir/image-manifests.txt"
  env_file="$stage_dir/resolved-images.env"
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
    if ! digest="$(python "$MANIFEST_PARSER" - "$IMAGE_PLATFORM" <<<"$manifest")"; then
      printf 'Mirror %s lacks a %s descriptor for %s.\n' "$prefix" "$IMAGE_PLATFORM" "$reference" >&2
      accepted=0
      break
    fi
    if [[ ! "$digest" =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
      printf 'Mirror %s returned no content digest for %s.\n' "$prefix" "$reference" >&2
      accepted=0
      break
    fi
    printf '%s\t%s\t%s\n' "$key" "$reference" "$digest" >>"$manifest_file"
    printf '%s_IMAGE_REF=%s@%s\n' "$key" "$reference" "$digest" >>"$env_file"
  done

  if (( accepted )); then
    release_dir="$RESOLUTION_ROOT/release-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mv "$stage_dir" "$release_dir"
    stage_dir=
    printf 'IMAGE_RESOLUTION_COMMITTED=1\n' >"$release_dir/commit"
    printf 'IMAGE_RESOLUTION_READY=1\n' >"$release_dir/ready"
    publish_link "image-resolution/current/resolved-images.env" "$STACK_ROOT/resolved-images.env"
    publish_link "../image-resolution/current/image-manifests.txt" "$STACK_ROOT/reports/image-manifests.txt"
    current_tmp="$RESOLUTION_ROOT/.current.$$"
    rm -f "$current_tmp"
    ln -s "$(basename "$release_dir")" "$current_tmp"
    mv -f "$current_tmp" "$CURRENT_LINK"
    published=1
    trap - EXIT
    printf 'Resolved all images through mirror %s.\n' "$prefix"
    exit 0
  fi

  rm -rf "$stage_dir"
  stage_dir=
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
  printf 'DRY RUN: upload manifest probe payload and structured JSON parser to %s:%s.\n' "$REMOTE_HOST" "$REMOTE_PATH"
  printf 'DRY RUN: inspect all exact image tags with docker manifest inspect --verbose for linux/amd64.\n'
  printf 'DRY RUN: publish ready and commit marked image resolution under %s/image-resolution/current.\n' "$REMOTE_STACK_ROOT"
  printf '%s\n' "$REMOTE_SCRIPT"
  exit 0
fi

payload="$(mktemp "${TMPDIR:-/tmp}/middleware-probe-images.XXXXXX")"
trap 'rm -f "$payload"' EXIT
printf '%s\n' "$REMOTE_SCRIPT" >"$payload"
run scp -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$PARSER" "$REMOTE_HOST:$REMOTE_PARSER_PATH"
run scp -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$payload" "$REMOTE_HOST:$REMOTE_PATH"
remote "bash $REMOTE_PATH"
