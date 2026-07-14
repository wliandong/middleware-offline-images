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
if grep -F 'timedatectl show -p' <<<"$preflight_payload"; then
  printf 'Preflight payload must not use unsupported timedatectl show -p.\n' >&2
  exit 1
fi
grep -F 'chronyc tracking' <<<"$preflight_payload"
grep -F 'Leap status.*Normal' <<<"$preflight_payload"
grep -F 'timedatectl status' <<<"$preflight_payload"
grep -F 'NTP synchronized:' <<<"$preflight_payload"
chrony_line="$(line_number 'chronyc tracking' "$preflight_payload")"
timedatectl_line="$(line_number 'timedatectl status' "$preflight_payload")"
test -n "$chrony_line"
test -n "$timedatectl_line"
test "$chrony_line" -lt "$timedatectl_line"
grep -F 'yum install -y yum-utils device-mapper-persistent-data lvm2' <<<"$install_payload"
grep -F 'if [[ -s /etc/docker/daemon.json ]]; then' <<<"$install_payload"
grep -F 'Refusing to overwrite non-empty /etc/docker/daemon.json.' <<<"$install_payload"
grep -F 'mktemp /etc/docker/daemon.json.XXXXXX' <<<"$install_payload"
grep -F 'install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json' <<<"$install_payload"
grep -F 'yum --enablerepo=rhel-7-server-extras-rpms install -y container-selinux fuse-overlayfs slirp4netns' <<<"$install_payload"

if grep -E 'yum-config-manager[[:space:]].*--enable[[:space:]]+rhel-7-server-extras-rpms|subscription-manager[[:space:]]+repos[[:space:]].*--enable.*rhel-7-server-extras-rpms' <<<"$install_payload"; then
  printf 'Installer must not permanently enable the RHEL extras repository.\n' >&2
  exit 1
fi

if grep -E '(^|[[:space:]])(ssh|scp)[[:space:]]' <<<"$preflight_payload$install_payload"; then
  printf 'Payload-print mode must not run SSH or SCP.\n' >&2
  exit 1
fi

assert_before 'if [[ -s /etc/docker/daemon.json ]]; then' 'yum install -y yum-utils device-mapper-persistent-data lvm2'
assert_before 'yum install -y yum-utils device-mapper-persistent-data lvm2' 'yum-config-manager --add-repo'
assert_before 'yum-config-manager --add-repo' 'yum --enablerepo=rhel-7-server-extras-rpms install -y container-selinux fuse-overlayfs slirp4netns'
assert_before 'yum --enablerepo=rhel-7-server-extras-rpms install -y container-selinux fuse-overlayfs slirp4netns' 'if ! yum list available "docker-ce-${DOCKER_CE_VERSION}"'
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

probe_output="$(DRY_RUN=1 bash "$ROOT/scripts/02-probe-images.sh")"
probe_payload="$(PRINT_REMOTE_SCRIPT=1 bash "$ROOT/scripts/02-probe-images.sh")"
grep -F 'docker manifest inspect --verbose' <<<"$probe_payload"
grep -F "MIRROR_PREFIXES='docker.1ms.run docker.m.daocloud.io dockerproxy.net'" <<<"$probe_payload"
grep -F "MYSQL_IMAGE='library/mysql:8.4.10'" <<<"$probe_payload"
grep -F 'reference="${prefix}/${image}"' <<<"$probe_payload"
grep -F 'linux/amd64' <<<"$probe_payload"
grep -F 'resolved-images.env' <<<"$probe_output"
if grep -E '(^|[[:space:]])(ssh|scp)[[:space:]]' <<<"$probe_payload"; then
  printf 'Probe payload-print mode must not run SSH or SCP.\n' >&2
  exit 1
fi

render_fixture="$(mktemp -d "${TMPDIR:-/tmp}/middleware-render-test.XXXXXX")"
trap 'rm -rf "$render_fixture"' EXIT
mkdir -p "$render_fixture/resolution"
printf '%s\n' 'REDIS_PASSWORD=dry-run-secret' >"$render_fixture/.env"
printf '%s\n' 'MYSQL_IMAGE_REF=docker.1ms.run/library/mysql:8.4.10@sha256:example' >"$render_fixture/resolved-images.env"
printf '%s\n' 'IMAGE_RESOLUTION_READY=1' >"$render_fixture/resolution/ready"
printf '%s\n' 'IMAGE_RESOLUTION_COMMITTED=1' >"$render_fixture/resolution/commit"
render_output="$(DRY_RUN=1 ENV_FILE="$render_fixture/.env" RESOLVED_IMAGES_FILE="$render_fixture/resolved-images.env" RESOLUTION_DIR="$render_fixture/resolution" bash "$ROOT/scripts/04-render-config.sh")"
grep -F 'mode 0600' <<<"$render_output"
grep -F 'docker compose' <<<"$render_output"
grep -F 'config --quiet' <<<"$render_output"
if grep -F 'dry-run-secret' <<<"$render_output"; then
  printf 'Render dry-run output must not print secrets.\n' >&2
  exit 1
fi

printf 'Dry-run tests passed.\n'
