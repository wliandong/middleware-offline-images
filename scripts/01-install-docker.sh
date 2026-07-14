#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

REMOTE_PATH=/tmp/middleware-install-docker.sh
REMOTE_SCRIPT="$(cat <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DOCKER_CE_VERSION='__DOCKER_CE_VERSION__'
DOCKER_ROOT='__DOCKER_ROOT__'

if [[ -s /etc/docker/daemon.json ]]; then
  printf 'Refusing to overwrite non-empty /etc/docker/daemon.json.\n' >&2
  exit 1
fi

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum --enablerepo=rhel-7-server-extras-rpms install -y container-selinux fuse-overlayfs slirp4netns
if ! yum list available "docker-ce-${DOCKER_CE_VERSION}" >/dev/null 2>&1; then
  printf 'Docker CE %s is unavailable; no alternate version will be installed.\n' "${DOCKER_CE_VERSION}" >&2
  exit 1
fi
yum install -y "docker-ce-${DOCKER_CE_VERSION}" "docker-ce-cli-${DOCKER_CE_VERSION}" containerd.io docker-buildx-plugin docker-compose-plugin
install -d -m 0755 "${DOCKER_ROOT}" /etc/docker
daemon_tmp="$(mktemp /etc/docker/daemon.json.XXXXXX)"
trap 'rm -f "$daemon_tmp"' EXIT
cat >"${daemon_tmp}" <<'JSON'
{
  "data-root": "/home/docker-data",
  "storage-driver": "overlay2",
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  }
}
JSON
install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json
rm -f "${daemon_tmp}"
trap - EXIT
systemctl enable --now docker
test "$(docker version --format '{{.Server.Version}}')" = "${DOCKER_CE_VERSION}"
test "$(docker info --format '{{.Driver}}')" = overlay2
test "$(docker info --format '{{.DockerRootDir}}')" = "${DOCKER_ROOT}"
docker compose version
REMOTE_SCRIPT
)"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__DOCKER_CE_VERSION__/$DOCKER_CE_VERSION}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__DOCKER_ROOT__/$REMOTE_DOCKER_ROOT}"

if [[ "${PRINT_REMOTE_SCRIPT:-0}" == "1" ]]; then
  printf '%s\n' "$REMOTE_SCRIPT"
  exit 0
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY RUN: upload %s to %s:%s\n' "$REMOTE_PATH" "$REMOTE_HOST" "$REMOTE_PATH"
  printf 'DRY RUN: install Docker CE %s using https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo\n' "$DOCKER_CE_VERSION"
  printf 'DRY RUN: configure /etc/docker/daemon.json with data-root=%s, storage-driver=overlay2, live-restore=true, json-file max-size=100m max-file=5\n' "$REMOTE_DOCKER_ROOT"
  printf 'DRY RUN: verify Docker server version, storage driver, Docker Root Dir, and Compose version.\n'
  run scp -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$REMOTE_PATH" "$REMOTE_HOST:$REMOTE_PATH"
  remote "bash $REMOTE_PATH"
  exit 0
fi

payload="$(mktemp "${TMPDIR:-/tmp}/middleware-install-docker.XXXXXX")"
trap 'rm -f "$payload"' EXIT
printf '%s\n' "$REMOTE_SCRIPT" >"$payload"
run scp -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$payload" "$REMOTE_HOST:$REMOTE_PATH"
remote "bash $REMOTE_PATH"
