#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preflight_output="$(DRY_RUN=1 bash "$ROOT/scripts/00-preflight.sh")"
install_output="$(DRY_RUN=1 bash "$ROOT/scripts/01-install-docker.sh")"
preflight_payload="$(PRINT_REMOTE_SCRIPT=1 bash "$ROOT/scripts/00-preflight.sh")"
install_payload="$(PRINT_REMOTE_SCRIPT=1 bash "$ROOT/scripts/01-install-docker.sh")"

line_number() {
  grep -nF "$1" <<<"$2" | head -n 1 | cut -d: -f1
}

assert_before() {
  local first second first_line second_line
  first="$1"
  second="$2"
  first_line="$(line_number "$first" "$install_payload")"
  second_line="$(line_number "$second" "$install_payload")"
  test -n "$first_line"
  test -n "$second_line"
  test "$first_line" -lt "$second_line"
}

grep -F 'lscpu' <<<"$preflight_output"
grep -F 'xfs_info' <<<"$preflight_output"
grep -F 'preflight-local.txt' <<<"$preflight_output"

grep -F '26.1.4' <<<"$install_output"
grep -F '/home/docker-data' <<<"$install_output"
grep -F 'mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo' <<<"$install_output"
grep -F '/etc/docker/daemon.json' <<<"$install_output"

grep -F 'lscpu' <<<"$preflight_payload"
grep -F 'xfs_info /home' <<<"$preflight_payload"
grep -F 'yum install -y yum-utils device-mapper-persistent-data lvm2' <<<"$install_payload"
grep -F 'if [[ -s /etc/docker/daemon.json ]]; then' <<<"$install_payload"
grep -F 'Refusing to overwrite non-empty /etc/docker/daemon.json.' <<<"$install_payload"
grep -F 'mktemp /etc/docker/daemon.json.XXXXXX' <<<"$install_payload"
grep -F 'install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json' <<<"$install_payload"

if grep -E '(^|[[:space:]])(ssh|scp)[[:space:]]' <<<"$preflight_payload$install_payload"; then
  printf 'Payload-print mode must not run SSH or SCP.\n' >&2
  exit 1
fi

assert_before 'if [[ -s /etc/docker/daemon.json ]]; then' 'yum install -y yum-utils device-mapper-persistent-data lvm2'
assert_before 'yum install -y yum-utils device-mapper-persistent-data lvm2' 'yum-config-manager --add-repo'
assert_before 'yum-config-manager --add-repo' 'if ! yum list available "docker-ce-${DOCKER_CE_VERSION}"'
assert_before 'if ! yum list available "docker-ce-${DOCKER_CE_VERSION}"' 'yum install -y "docker-ce-${DOCKER_CE_VERSION}"'
assert_before 'yum install -y "docker-ce-${DOCKER_CE_VERSION}"' 'install -d -m 0755'
assert_before 'install -d -m 0755' 'mktemp /etc/docker/daemon.json.XXXXXX'
assert_before 'mktemp /etc/docker/daemon.json.XXXXXX' 'systemctl enable --now docker'
assert_before 'install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json' 'systemctl enable --now docker'
assert_before 'systemctl enable --now docker' 'docker version --format'
assert_before 'docker version --format' "docker info --format '{{.Driver}}'"
assert_before "docker info --format '{{.Driver}}'" "docker info --format '{{.DockerRootDir}}'"
assert_before "docker info --format '{{.DockerRootDir}}'" 'docker compose version'

if grep -E '(^|[[:space:]])systemctl[[:space:]]+stop[[:space:]]+[^[:space:]]*(mysql|redis|mongo)[^[:space:]]*|(^|[[:space:]])service[[:space:]]+[^[:space:]]*(mysql|redis|mongo)[^[:space:]]*[[:space:]]+stop' <<<"$preflight_payload$install_payload"; then
  printf 'Dry run must not stop legacy services.\n' >&2
  exit 1
fi

printf 'Dry-run tests passed.\n'
