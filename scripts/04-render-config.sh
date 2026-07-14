#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
RESOLVED_IMAGES_FILE="${RESOLVED_IMAGES_FILE:-$ROOT/resolved-images.env}"
TEMPLATE="$ROOT/config/redis/redis.conf.template"
RENDERED_CONFIG="$ROOT/runtime/redis/redis.conf"
COMPOSE_FILE="$ROOT/compose/docker-compose.yml"

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Required file is missing: %s\n' "$1" >&2
    exit 1
  fi
}

require_secret() {
  local name="$1"
  local value="${!name:-}"
  local normalized
  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    ''|*example*|*change-me*|*changeme*|*replace*|password|secret)
      printf '%s must be a non-example password.\n' "$name" >&2
      exit 1
      ;;
  esac
}

require_file "$ENV_FILE"
require_file "$RESOLVED_IMAGES_FILE"
require_file "$TEMPLATE"
require_file "$COMPOSE_FILE"

set -a
source "$ENV_FILE"
source "$RESOLVED_IMAGES_FILE"
set +a
require_secret REDIS_PASSWORD

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY RUN: render Redis configuration at %s with mode 0600.\n' "$RENDERED_CONFIG"
  printf 'DRY RUN: validate Compose with docker compose --env-file %s --env-file %s -f %s config --quiet.\n' "$RESOLVED_IMAGES_FILE" "$ENV_FILE" "$COMPOSE_FILE"
  exit 0
fi

install -d -m 0700 "$(dirname "$RENDERED_CONFIG")"
temporary_config="$(mktemp "$(dirname "$RENDERED_CONFIG")/.redis.conf.XXXXXX")"
trap 'rm -f "$temporary_config"' EXIT

escaped_password="$REDIS_PASSWORD"
escaped_password="${escaped_password//\\/\\\\}"
escaped_password="${escaped_password//\"/\\\"}"
escaped_password="${escaped_password//&/\\&}"
escaped_password="${escaped_password//|/\\|}"
sed "s|__REDIS_PASSWORD__|${escaped_password}|g" "$TEMPLATE" >"$temporary_config"
install -m 0600 "$temporary_config" "$RENDERED_CONFIG"
rm -f "$temporary_config"
trap - EXIT

docker compose --env-file "$RESOLVED_IMAGES_FILE" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet
printf 'Rendered Redis configuration and validated Compose configuration.\n'
