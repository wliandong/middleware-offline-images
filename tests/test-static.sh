#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

test "$MYSQL_VERSION" = "8.4.10"
test "$REDIS_VERSION" = "8.8"
test "$MONGODB_VERSION" = "8.0.26"
test "$KAFKA_VERSION" = "4.3.1"
test "$REDIS_UID" = "999"
test "$REDIS_GID" = "999"
test "$KAFKA_UID" = "1000"
test "$KAFKA_GID" = "1000"
test "$KAFKA_DATA_DIR" = "/home/middleware-test/data/kafka"
test "$IMAGE_PLATFORM" = "linux/amd64"
test "$MYSQL_IMAGE" = "library/mysql:8.4.10"
test "$REDIS_IMAGE" = "library/redis:8.8"
test "$MONGODB_IMAGE" = "library/mongo:8.0.26"
test "$KAFKA_IMAGE" = "apache/kafka:4.3.1"
test "$MIRROR_PREFIXES" = "docker.1ms.run docker.m.daocloud.io dockerproxy.net"
test "$REMOTE_HOST" = "root@192.168.0.28"
test "$REMOTE_IDENTITY" = "/Users/wangliandong/.ssh/codex_192_168_0_28"
test "$REMOTE_STACK_ROOT" = "/home/middleware-test"
test "$REMOTE_DOCKER_ROOT" = "/home/docker-data"
test "$MYSQL_PORT" = "127.0.0.1:3306"
test "$REDIS_PORT" = "127.0.0.1:6379"
test "$MONGODB_PORT" = "127.0.0.1:27017"
test "$KAFKA_PORT" = "127.0.0.1:9092"
declare -F run require_command sha256_file remote >/dev/null

CHECKPOINT="$ROOT/checkpoints/task-01.sha256"
if grep -Fq 'checkpoints/task-01.sha256' "$CHECKPOINT"; then
  printf 'checkpoint must not include itself\n' >&2
  exit 1
fi
test "$(wc -l < "$CHECKPOINT" | tr -d '[:space:]')" = "4"
for file in .env.example versions.env scripts/lib/common.sh tests/test-static.sh; do
  grep -Fq "./$file" "$CHECKPOINT"
done
shasum -a 256 -c "$CHECKPOINT" >/dev/null

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/compose/docker-compose.yml}"
PROBE_SCRIPT="$ROOT/scripts/02-probe-images.sh"
RENDER_SCRIPT="$ROOT/scripts/04-render-config.sh"

for file in \
  "$COMPOSE_FILE" \
  "$PROBE_SCRIPT" \
  "$RENDER_SCRIPT" \
  "$ROOT/config/mysql/my.cnf" \
  "$ROOT/config/redis/redis.conf.template" \
  "$ROOT/config/mongodb/mongod.conf" \
  "$ROOT/init/mysql/10-create-app-user.sh" \
  "$ROOT/init/mongodb/10-create-app-user.js"; do
  test -f "$file"
done

service_block() {
  awk -v service="$1" '
    $0 == "  " service ":" { capture = 1 }
    capture && $0 ~ /^  [[:alnum:]_-]+:$/ && $0 != "  " service ":" { exit }
    capture { print }
  ' "$COMPOSE_FILE"
}

for service in mysql redis mongodb kafka; do
  block="$(service_block "$service")"
  test -n "$block"
  grep -F 'platform: linux/amd64' <<<"$block"
  grep -F 'restart: unless-stopped' <<<"$block"
  grep -F 'healthcheck:' <<<"$block"
  grep -F 'ulimits:' <<<"$block"
  grep -F ':Z' <<<"$block"
done

grep -F 'mem_limit: 4g' <<<"$(service_block mysql)"
grep -F 'mem_limit: 2g' <<<"$(service_block redis)"
grep -F 'mem_limit: 4g' <<<"$(service_block mongodb)"
grep -F 'mem_limit: 3g' <<<"$(service_block kafka)"

for port in 3306 6379 27017 9092; do
  grep -Fq "127.0.0.1:${port}:${port}" "$COMPOSE_FILE"
done
port_mappings=()
while IFS= read -r mapping; do
  port_mappings+=("$mapping")
done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*"([^"]*:[0-9]+:[0-9]+)".*/\1/p' "$COMPOSE_FILE")
for mapping in "${port_mappings[@]}"; do
  case "$mapping" in
    127.0.0.1:3306:3306|127.0.0.1:6379:6379|127.0.0.1:27017:27017|127.0.0.1:9092:9092) ;;
    *) printf 'Unexpected non-loopback or extra port mapping: %s\n' "$mapping" >&2; exit 1 ;;
  esac
done
test "${#port_mappings[@]}" = "4"
grep -F 'driver: bridge' "$COMPOSE_FILE"
grep -F 'internal: true' "$COMPOSE_FILE"

kafka_block="$(service_block kafka)"
grep -F 'user: "${KAFKA_UID:-1000}:${KAFKA_GID:-1000}"' <<<"$kafka_block"
grep -F '${KAFKA_DATA_DIR:-/home/middleware-test/data/kafka}' <<<"$kafka_block"
grep -F 'KAFKA_PROCESS_ROLES: broker,controller' <<<"$kafka_block"
grep -F 'KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:29093' <<<"$kafka_block"
grep -F 'KAFKA_ADVERTISED_LISTENERS: PLAINTEXT_HOST://127.0.0.1:9092,PLAINTEXT://kafka:29092' <<<"$kafka_block"
grep -F 'KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT' <<<"$kafka_block"
grep -F 'bootstrap-server kafka:29092' <<<"$kafka_block"

grep -F 'character-set-server = utf8mb4' "$ROOT/config/mysql/my.cnf"
grep -F 'skip-name-resolve = ON' "$ROOT/config/mysql/my.cnf"
grep -F 'innodb_buffer_pool_size = 2G' "$ROOT/config/mysql/my.cnf"
grep -F 'log_bin = mysql-bin' "$ROOT/config/mysql/my.cnf"
grep -F "default-time-zone = '+00:00'" "$ROOT/config/mysql/my.cnf"
grep -F 'appendonly yes' "$ROOT/config/redis/redis.conf.template"
grep -F 'maxmemory 1536mb' "$ROOT/config/redis/redis.conf.template"
grep -F 'maxmemory-policy noeviction' "$ROOT/config/redis/redis.conf.template"
grep -F '__REDIS_PASSWORD__' "$ROOT/config/redis/redis.conf.template"
grep -F 'authorization: enabled' "$ROOT/config/mongodb/mongod.conf"
grep -F 'cacheSizeGB: 2' "$ROOT/config/mongodb/mongod.conf"
grep -F 'CREATE DATABASE IF NOT EXISTS' "$ROOT/init/mysql/10-create-app-user.sh"
grep -F 'appdb' "$ROOT/init/mysql/10-create-app-user.sh"
grep -F 'process.env.MONGODB_USER' "$ROOT/init/mongodb/10-create-app-user.js"
grep -F 'appdb' "$ROOT/init/mongodb/10-create-app-user.js"

grep -F 'docker manifest inspect --verbose' "$PROBE_SCRIPT"
grep -F 'linux/amd64' "$PROBE_SCRIPT"
grep -F 'image-manifests.txt' "$PROBE_SCRIPT"
grep -F 'resolved-images.env' "$PROBE_SCRIPT"
grep -F 'PRINT_REMOTE_SCRIPT' "$PROBE_SCRIPT"
grep -F 'DRY_RUN' "$PROBE_SCRIPT"
grep -F 'install -m 0600' "$RENDER_SCRIPT"
grep -F 'chown "$REDIS_UID:$REDIS_GID"' "$RENDER_SCRIPT"
grep -F 'IMAGE_RESOLUTION_READY=1' "$RENDER_SCRIPT"
grep -F 'IMAGE_RESOLUTION_COMMITTED=1' "$RENDER_SCRIPT"
grep -F 'docker compose' "$RENDER_SCRIPT"
grep -F 'config --quiet' "$RENDER_SCRIPT"
grep -F '.env' "$RENDER_SCRIPT"

if rg -n 'latest' "$COMPOSE_FILE" "$PROBE_SCRIPT" "$RENDER_SCRIPT"; then
  printf 'Task 3 files must not use a latest tag.\n' >&2
  exit 1
fi
