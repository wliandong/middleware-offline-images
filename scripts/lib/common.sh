#!/usr/bin/env bash

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    return 1
  fi
}

sha256_file() {
  shasum -a 256 "$1"
}

remote() {
  run ssh \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -i "$REMOTE_IDENTITY" \
    "$REMOTE_HOST" \
    "$@"
}
