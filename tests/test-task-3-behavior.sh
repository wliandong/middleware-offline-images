#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE="${TEST_CASE:-all}"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

test_manifest_digest() {
  digest="$(DRY_RUN=1 bash "$ROOT/scripts/02-probe-images.sh" --select-manifest-digest "$ROOT/tests/fixtures/manifest-multiarch.json")"
  test "$digest" = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
}

test_cleanup_traps_are_process_scoped() {
  local cleanup_signal="RET""URN"
  if grep -En "trap .*${cleanup_signal}" "$ROOT/tests/test-task-3-behavior.sh"; then
    fail 'Behavior scenarios must not leak RETURN cleanup traps into their caller.'
  fi
}

test_mysql_init_sql() (
  local temp_dir fake_bin
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/middleware-mysql-init.XXXXXX")"
  trap 'rm -rf "$temp_dir"' EXIT
  fake_bin="$temp_dir/bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/mysql" <<'SCRIPT'
#!/usr/bin/env bash
cat >"$MYSQL_CAPTURE"
SCRIPT
  cat >"$fake_bin/appdb" <<'SCRIPT'
#!/usr/bin/env bash
printf 'appdb command was invoked\n' >"$MYSQL_COMMAND_MARKER"
exit 99
SCRIPT
  chmod 0755 "$fake_bin/mysql" "$fake_bin/appdb"

  PATH="$fake_bin:$PATH" \
    MYSQL_CAPTURE="$temp_dir/query.sql" \
    MYSQL_COMMAND_MARKER="$temp_dir/appdb-invoked" \
    MYSQL_ROOT_PASSWORD=root-password \
    MYSQL_DATABASE=appdb \
    MYSQL_USER=app_user \
    MYSQL_PASSWORD="app'password" \
    bash "$ROOT/init/mysql/10-create-app-user.sh"

  test ! -e "$temp_dir/appdb-invoked"
  grep -F 'CREATE DATABASE IF NOT EXISTS `appdb`' "$temp_dir/query.sql"
  grep -F "CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED BY 'app''password';" "$temp_dir/query.sql"
  expected_grant="GRANT ALL PRIVILEGES ON \`appdb\`.* TO 'app_user'@'%';"
  grep -F "$expected_grant" "$temp_dir/query.sql"
)

test_public_port_rejected() (
  local temp_compose
  temp_compose="$(mktemp "${TMPDIR:-/tmp}/middleware-compose.XXXXXX")"
  trap 'rm -f "$temp_compose"' EXIT
  awk '
    /127\.0\.0\.1:3306:3306/ {
      print
      print "      - \"0.0.0.0:3307:3306\""
      next
    }
    { print }
  ' "$ROOT/compose/docker-compose.yml" >"$temp_compose"

  if output="$(COMPOSE_FILE="$temp_compose" bash "$ROOT/tests/test-static.sh" 2>&1)"; then
    fail 'Static validation accepted a public port mapping.'
  fi
  grep -F 'Unexpected non-loopback or extra port mapping: 0.0.0.0:3307:3306' <<<"$output"
)

prepare_resolution_fixture() {
  local temp_dir="$1"
  mkdir -p "$temp_dir/resolution"
  printf '%s\n' 'MYSQL_IMAGE_REF=example.invalid/mysql@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' >"$temp_dir/resolved-images.env"
  printf '%s\n' 'REDIS_PASSWORD=fixture-secret' >"$temp_dir/.env"
}

test_ready_marker_required() (
  local temp_dir output payload commit_line ready_line
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/middleware-resolution.XXXXXX")"
  trap 'rm -rf "$temp_dir"' EXIT
  prepare_resolution_fixture "$temp_dir"

  payload="$(PRINT_REMOTE_SCRIPT=1 bash "$ROOT/scripts/02-probe-images.sh")"
  commit_line="$(grep -nF "IMAGE_RESOLUTION_COMMITTED=1" <<<"$payload" | cut -d: -f1)"
  ready_line="$(grep -nF "IMAGE_RESOLUTION_READY=1" <<<"$payload" | cut -d: -f1)"
  test -n "$commit_line"
  test -n "$ready_line"
  test "$commit_line" -lt "$ready_line"

  if DRY_RUN=1 ENV_FILE="$temp_dir/.env" RESOLVED_IMAGES_FILE="$temp_dir/resolved-images.env" RESOLUTION_DIR="$temp_dir/resolution" \
    bash "$ROOT/scripts/04-render-config.sh"; then
    fail 'Renderer accepted unresolved image metadata without ready and commit markers.'
  fi

  printf '%s\n' 'IMAGE_RESOLUTION_READY=1' >"$temp_dir/resolution/ready"
  printf '%s\n' 'IMAGE_RESOLUTION_COMMITTED=1' >"$temp_dir/resolution/commit"
  output="$(DRY_RUN=1 ENV_FILE="$temp_dir/.env" RESOLVED_IMAGES_FILE="$temp_dir/resolved-images.env" RESOLUTION_DIR="$temp_dir/resolution" \
    bash "$ROOT/scripts/04-render-config.sh")"
  grep -F 'config --quiet' <<<"$output"
)

test_redis_owner_contract() (
  local temp_dir fake_bin output
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/middleware-redis-render.XXXXXX")"
  trap 'rm -rf "$temp_dir" "$ROOT/runtime"' EXIT
  fake_bin="$temp_dir/bin"
  mkdir -p "$fake_bin" "$temp_dir/resolution"
  cat >"$fake_bin/docker" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOCKER_CAPTURE"
SCRIPT
  cat >"$fake_bin/chown" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHOWN_CAPTURE"
SCRIPT
  chmod 0755 "$fake_bin/docker" "$fake_bin/chown"
  printf '%s\n' 'REDIS_PASSWORD=fixture-secret' 'REDIS_UID=4242' 'REDIS_GID=4343' >"$temp_dir/.env"
  printf '%s\n' 'MYSQL_IMAGE_REF=example.invalid/mysql@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' >"$temp_dir/resolved-images.env"
  printf '%s\n' 'IMAGE_RESOLUTION_READY=1' >"$temp_dir/resolution/ready"
  printf '%s\n' 'IMAGE_RESOLUTION_COMMITTED=1' >"$temp_dir/resolution/commit"

  output="$(PATH="$fake_bin:$PATH" DOCKER_CAPTURE="$temp_dir/docker.log" CHOWN_CAPTURE="$temp_dir/chown.log" \
    ENV_FILE="$temp_dir/.env" RESOLVED_IMAGES_FILE="$temp_dir/resolved-images.env" RESOLUTION_DIR="$temp_dir/resolution" \
    RENDERED_CONFIG="$temp_dir/redis.conf" bash "$ROOT/scripts/04-render-config.sh")"
  test "$(stat -f '%Lp' "$temp_dir/redis.conf")" = "600"
  grep -F '4242:4343' "$temp_dir/chown.log"
  if grep -F 'fixture-secret' <<<"$output"; then
    fail 'Renderer output leaked the Redis password.'
  fi
)

test_checkpoint_boundaries() {
  if grep -Fq 'scripts/02-probe-images.sh' "$ROOT/checkpoints/task-02.sha256"; then
    fail 'Task 2 checkpoint contains Task 3 scripts.'
  fi
  if grep -Eq 'scripts/(00-preflight|01-install-docker|lib/common)\.sh' "$ROOT/checkpoints/task-03.sha256"; then
    fail 'Task 3 checkpoint contains Task 1 or Task 2 scripts.'
  fi
}

case "$CASE" in
  manifest) test_manifest_digest ;;
  cleanup) test_cleanup_traps_are_process_scoped ;;
  mysql) test_mysql_init_sql ;;
  ports) test_public_port_rejected ;;
  ready) test_ready_marker_required ;;
  redis) test_redis_owner_contract ;;
  checkpoints) test_checkpoint_boundaries ;;
  all)
    for test_case in manifest cleanup mysql ports ready redis checkpoints; do
      TEST_CASE="$test_case" bash "$0"
    done
    ;;
  *) fail "Unknown TEST_CASE: $CASE" ;;
esac

printf 'Task 3 behavior tests passed.\n'
