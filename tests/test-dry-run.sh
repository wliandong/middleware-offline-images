#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preflight_output="$(DRY_RUN=1 bash "$ROOT/scripts/00-preflight.sh")"
install_output="$(DRY_RUN=1 bash "$ROOT/scripts/01-install-docker.sh")"

grep -F 'lscpu' <<<"$preflight_output"
grep -F 'xfs_info' <<<"$preflight_output"
grep -F 'preflight-local.txt' <<<"$preflight_output"

grep -F '26.1.4' <<<"$install_output"
grep -F '/home/docker-data' <<<"$install_output"
grep -F 'mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo' <<<"$install_output"
grep -F '/etc/docker/daemon.json' <<<"$install_output"

if grep -E 'systemctl stop (mysqld|redis|mongod)' <<<"$preflight_output$install_output"; then
  printf 'Dry run must not stop legacy services.\n' >&2
  exit 1
fi

printf 'Dry-run tests passed.\n'
