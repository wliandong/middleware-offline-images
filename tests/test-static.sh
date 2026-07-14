#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

test "$MYSQL_VERSION" = "8.4.10"
test "$REDIS_VERSION" = "8.8"
test "$MONGODB_VERSION" = "8.0.26"
test "$KAFKA_VERSION" = "4.3.1"
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
