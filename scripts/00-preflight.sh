#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"
source "$ROOT/scripts/lib/common.sh"

REPORT="$ROOT/reports/preflight-local.txt"
REMOTE_SCRIPT="$(cat <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

fail=0
check_hard() {
  if "$@"; then
    printf 'PASS: %s\n' "$*"
  else
    printf 'FAIL: %s\n' "$*" >&2
    fail=1
  fi
}

printf 'Preflight timestamp: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Release: '; cat /etc/redhat-release
check_hard grep -Eq 'Red Hat.*release 7\.9' /etc/redhat-release
printf 'Architecture: '; uname -m
check_hard test "$(uname -m)" = x86_64
check_hard sh -c "lscpu | grep -Eiq '(^|[[:space:]])avx([[:space:]]|$)'"
check_hard sh -c "xfs_info /home | grep -Eq 'ftype=1'"
check_hard sh -c "test \"$(df -Pk /home | awk 'NR == 2 { print $4 }')\" -ge 12582912"

if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qx yes; then
  printf 'PASS: NTP synchronized\n'
else
  printf 'FAIL: NTP synchronized\n' >&2
  fail=1
fi

printf 'SELinux mode: '
getenforce 2>/dev/null || printf 'unavailable\n'
printf 'Listening ports:\n'
ss -ltnup 2>/dev/null || netstat -ltnup 2>/dev/null || true
printf 'Legacy service units:\n'
systemctl list-unit-files 2>/dev/null | grep -E '^(mysqld|mysql|redis|redis-server|mongod)(\.service)?[[:space:]]' || true

if (( fail )); then
  printf 'Preflight failed; no changes were made.\n' >&2
  exit 1
fi
REMOTE_SCRIPT
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'DRY RUN: remote preflight checks /etc/redhat-release, uname -m, lscpu, xfs_info /home, df -Pk /home, timedatectl, getenforce, ss, and systemctl list-unit-files.\n'
  printf 'DRY RUN: report would be written to %s\n' "$REPORT"
  run ssh -o IdentitiesOnly=yes -o BatchMode=yes -i "$REMOTE_IDENTITY" "$REMOTE_HOST" 'bash -s'
  exit 0
fi

mkdir -p "$(dirname "$REPORT")"
printf 'Preflight started: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$REPORT"
if ! printf '%s\n' "$REMOTE_SCRIPT" | remote 'bash -s' >>"$REPORT" 2>&1; then
  printf 'Preflight failed. See %s\n' "$REPORT" >&2
  exit 1
fi
printf 'Preflight passed. Report: %s\n' "$REPORT"
