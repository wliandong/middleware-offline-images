# Task 2 Report: Preflight and Docker Installation

## Implementation

- Added `scripts/00-preflight.sh`. It runs a read-only remote preflight for RHEL 7.9, x86_64, AVX, XFS `ftype=1`, 12 GB free space under `/home`, NTP synchronization, SELinux mode, listening ports, and legacy service units. Hard requirement failures exit before any changes. Normal runs save the timestamped output to `reports/preflight-local.txt`.
- Added `scripts/01-install-docker.sh`. It uploads an installation payload to `/tmp/middleware-install-docker.sh`, adds the Aliyun Docker CE mirror, refuses to proceed when Docker CE 26.1.4 is unavailable, installs the exact Docker packages, configures `/home/docker-data` and `/etc/docker/daemon.json`, enables Docker, and verifies server version, storage driver, root directory, and Compose.
- Added `tests/test-dry-run.sh`. It exercises both scripts with `DRY_RUN=1`, verifies the required Docker configuration output, and rejects legacy service stop commands.
- In dry-run mode both scripts only print planned operations; they do not invoke SSH, SCP, remote scripts, Docker, or service actions.

## RED

Command: `bash tests/test-dry-run.sh`

Key output: `bash: .../scripts/00-preflight.sh: No such file or directory`

Exit status: 127, as expected before the Task 2 scripts existed.

## GREEN and Verification

Commands:

```bash
bash -n scripts/00-preflight.sh scripts/01-install-docker.sh tests/test-dry-run.sh
bash tests/test-static.sh
bash tests/test-dry-run.sh
git diff --check
find scripts tests -type f -print0 | sort -z | xargs -0 shasum -a 256 > checkpoints/task-02.sha256
shasum -a 256 -c checkpoints/task-02.sha256
```

Results: all commands exited 0. The dry-run output included `26.1.4`, `/home/docker-data`, the Aliyun repository URL, and `/etc/docker/daemon.json`; no legacy service-stop command appeared. The SHA256 checkpoint verified all five scripts/tests as `OK`.

## Files

- `scripts/00-preflight.sh`
- `scripts/01-install-docker.sh`
- `tests/test-dry-run.sh`
- `checkpoints/task-02.sha256`
- `.superpowers/sdd/task-2-report.md`

## Self-check and Follow-up

- No real SSH, Docker installation, or legacy-service action was performed.
- The exact package availability guard depends on the remote Aliyun repository exposing `docker-ce-26.1.4`; an unavailable RPM fails safely without selecting another version.
- Preflight is intentionally read-only and must be run against the target host before installation.

## Review Fixes

### Cause and Changes

- The initial installer overwrote `/etc/docker/daemon.json` directly. The remote payload now exits with `Refusing to overwrite non-empty /etc/docker/daemon.json.` when that file exists and is non-empty, before any YUM, directory, or Docker operation. When the destination is absent or empty, the JSON is written to an `/etc/docker/daemon.json.XXXXXX` temporary file and published with `install -m 0644`.
- The initial dry-run test asserted only launcher summaries. Both Task 2 scripts now support `PRINT_REMOTE_SCRIPT=1`, which prints the generated remote payload and exits before SSH/SCP. The test inspects those payloads directly.
- The test rejects `systemctl stop` for any unit containing `mysql`, `redis`, or `mongo`, and `service <mysql|redis|mongo...> stop`, across both payloads.
- Payload order is asserted from the daemon safety guard through dependency install, mirror add, exact-version check, Docker install, directory creation, temporary daemon config write, Docker enable/start, and version/storage/root/Compose verification.

### RED

Command: `bash -n tests/test-dry-run.sh && bash tests/test-dry-run.sh`

Key output before implementation: the test exited 1 at its first payload assertion because `PRINT_REMOTE_SCRIPT=1` still returned only the old dry-run summary rather than `lscpu` and `xfs_info /home` payload content.

### GREEN and Coverage

Commands:

```bash
bash -n scripts/00-preflight.sh scripts/01-install-docker.sh tests/test-dry-run.sh
bash tests/test-static.sh
bash tests/test-dry-run.sh
find scripts tests -type f -print0 | sort -z | xargs -0 shasum -a 256 > checkpoints/task-02.sha256
shasum -a 256 -c checkpoints/task-02.sha256
git diff --check
```

Key output: `Dry-run tests passed.` and all five files in `checkpoints/task-02.sha256` returned `OK`. The payload checks exercised both scripts without SSH/SCP; no target-host connection, Docker installation, or legacy service action occurred.

## Follow-up Review Fix: Daemon Publish Order

- Added an explicit payload-order assertion that `install -m 0644 "${daemon_tmp}" /etc/docker/daemon.json` occurs strictly before `systemctl enable --now docker`.
- RED command: a temporary copy of the Task 2 scripts and test moved the publication command after `systemctl enable --now docker`, then ran `bash <temporary-root>/tests/test-dry-run.sh`.
- RED result: the test exited non-zero and printed `RED confirmed: deliberately reordered daemon publication failed the order assertion.` No SSH/SCP, Docker installation, or Docker startup occurred.
- GREEN commands: `bash -n scripts/00-preflight.sh scripts/01-install-docker.sh tests/test-dry-run.sh`, `bash tests/test-static.sh`, `bash tests/test-dry-run.sh`, and `shasum -a 256 -c checkpoints/task-02.sha256`.
- GREEN result: all commands exited 0; the dry-run test printed `Dry-run tests passed.` and all five checkpoint entries returned `OK`.

## RHEL 7.9 NTP Compatibility Fix

### Real Failure Evidence and Root Cause

- On the target RHEL 7.9 host, both `timedatectl show -p NTPSynchronized --value` and `timedatectl show -p NTPSynchronized` exited 1 with `timedatectl: invalid option -- 'p'`.
- The same host returned 0 from `chronyc tracking` and reported `Leap status : Normal`.
- Root cause: the preflight payload used a `timedatectl show -p` option form unsupported by this RHEL 7 implementation; the NTP service was synchronized and not the failing component.

### RED and GREEN

- RED command: `bash -n tests/test-dry-run.sh && bash tests/test-dry-run.sh`.
- RED result: exit 1 after printing the legacy payload line `if timedatectl show -p NTPSynchronized --value ...`; the new test reported `Preflight payload must not use unsupported timedatectl show -p.`
- Fix: the read-only payload now accepts `chronyc tracking` only when `Leap status.*Normal` matches, then falls back to `timedatectl status` matching `NTP synchronized: yes`; only both failures mark NTP as failed.
- GREEN commands: `bash -n scripts/00-preflight.sh scripts/01-install-docker.sh tests/test-dry-run.sh`, `bash tests/test-static.sh`, `bash tests/test-dry-run.sh`, and `shasum -a 256 -c checkpoints/task-02.sha256`.
- GREEN result: all commands exited 0; `Dry-run tests passed.` and all five checkpoint entries returned `OK`. The tests used only local payload-print and dry-run paths, without Docker, SSH, or service actions.

## RHEL 7 Extras Docker Dependency Fix

### Real Failure Evidence and Root Cause

- Docker CE 26.1.4 dependency resolution on the target failed because it requires `container-selinux >= 2:2.74`, `fuse-overlayfs >= 0.7`, and `slirp4netns >= 0.4`.
- The target's subscribed `rhel-7-server-extras-rpms` repository was disabled, but read-only queries confirmed it provides `container-selinux 2:2.119.2-1.911c772.el7_8`, `fuse-overlayfs 0.7.2-6.el7_8`, and `slirp4netns 0.4.3-4.el7_8`.
- Root cause: the payload added the Docker repository but did not make these extras-only dependencies available to the Docker CE transaction.

### RED and GREEN

- RED command: `bash -n tests/test-dry-run.sh && bash tests/test-dry-run.sh`.
- RED result: exit 1 because the payload lacked `yum --enablerepo=rhel-7-server-extras-rpms install -y container-selinux fuse-overlayfs slirp4netns`.
- Fix: after the daemon guard, base tool install, and Docker repository addition, the payload temporarily enables only that one YUM transaction to install the three dependencies before exact Docker CE availability and installation. It does not run `yum-config-manager --enable` or `subscription-manager repos --enable`.
- GREEN commands: `bash -n scripts/00-preflight.sh scripts/01-install-docker.sh tests/test-dry-run.sh`, `bash tests/test-static.sh`, `bash tests/test-dry-run.sh`, and `shasum -a 256 -c checkpoints/task-02.sha256`.
- GREEN result: all commands exited 0; `Dry-run tests passed.` and all five checkpoint entries returned `OK`. No SSH connection, local Docker installation, or Docker startup occurred.
