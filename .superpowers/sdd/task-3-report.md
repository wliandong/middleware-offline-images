# Task 3 Report: Image Probing and Compose Configuration

## Status

Complete and locally verified. No Docker engine, network request, SSH/SCP connection, image pull, virtual-machine action, or legacy-service action was performed.

## Implementation

- Added `scripts/02-probe-images.sh`. Its generated remote payload evaluates mirror prefixes in declared order, runs `docker manifest inspect --verbose` for the four exact image tags, requires a `linux/amd64` platform and content digest for every image, and accepts a prefix only when all four succeed. It writes the accepted source references and digests to `/home/middleware-test/reports/image-manifests.txt` and `/home/middleware-test/resolved-images.env`.
- Added `scripts/04-render-config.sh`. It requires `.env` and resolved images, rejects empty/example Redis passwords without printing them, writes the rendered Redis configuration with mode `0600`, and runs `docker compose ... config --quiet` in its normal deployment path.
- Added Compose, MySQL, Redis, MongoDB, and init configuration. All four services use `linux/amd64`, loopback-only ports, independent health checks, memory limits, restart policy, nofile ulimits, and SELinux `:Z` labels. Kafka is a single-node KRaft broker/controller with host listener `127.0.0.1:9092` and internal listener `kafka:29092`.
- Updated static and dry-run coverage and added `checkpoints/task-03.sha256`. Task 1 and Task 2 checkpoint entries were recomputed because their existing test files changed; Task 1 retained its required `./` path format.

## RED

- Before implementation, `bash tests/test-static.sh` exited 1 because Task 3 files were absent.
- `bash tests/test-dry-run.sh` exited 127 because `scripts/02-probe-images.sh` was absent.

## GREEN and Verification

The following local-only verification completed with exit code 0:

```bash
bash -n scripts/00-preflight.sh scripts/01-install-docker.sh scripts/02-probe-images.sh scripts/04-render-config.sh init/mysql/10-create-app-user.sh tests/test-static.sh tests/test-dry-run.sh
bash tests/test-static.sh
bash tests/test-dry-run.sh
shasum -a 256 -c checkpoints/task-01.sha256
shasum -a 256 -c checkpoints/task-02.sha256
shasum -a 256 -c checkpoints/task-03.sha256
git diff --check
```

The dry-run test inspected the remote manifest payload locally, confirmed it contains no SSH/SCP invocation in payload-print mode, and confirmed Redis render dry-run output does not contain the fixture password. Ignore rules also cover `.env`, generated resolved images, rendered runtime configuration, and reports.

## Follow-up

- The actual `docker manifest inspect` operations and `docker compose config --quiet` command intentionally remain unexecuted locally. They run only when the deployment workflow is executed against the target environment.

## Review Finding Closure

### RED and Root Cause Evidence

- The first rerun of `bash tests/test-task-3-behavior.sh` exited 1 after the manifest and MySQL scenarios. Running scenarios separately showed `manifest`, `mysql`, `ready`, `redis`, and `checkpoints` passed while `ports` failed.
- The previous same-process cleanup failure had already been mitigated by dispatching each scenario through `TEST_CASE=<name> bash tests/test-task-3-behavior.sh`, so the rerun did not reproduce an unbound local variable across scenarios. A focused regression check then failed with exit 1 and listed four remaining `trap ... RETURN` cleanup sites. This confirmed the underlying cleanup mechanism was still unsafe even though subprocess dispatch isolated its effects.
- `TEST_CASE=ready bash tests/test-task-3-behavior.sh` failed after adding an ordering assertion because the generated probe payload wrote `IMAGE_RESOLUTION_READY=1` before `IMAGE_RESOLUTION_COMMITTED=1`.
- The public-port fixture initially failed before its expected diagnostic because the static validator checked the mapping count before examining the injected `0.0.0.0:3307:3306` entry. During this cycle, Task 1 checkpoint validation also correctly rejected the modified `tests/test-static.sh` until its task-scoped checksum was regenerated.

### GREEN

- Cleanup functions now run in function subshells with `EXIT` traps. The aggregate test still launches each scenario in a separate Bash process, and a regression assertion rejects future `RETURN` cleanup traps.
- The image-resolution release writes its commit marker first and its ready marker last, before atomically switching the `current` symlink. The renderer requires the resolved file plus exact ready and commit marker contents.
- Static port validation now checks every discovered mapping against the four loopback-only mappings before checking the exact count, so an extra public mapping is rejected with a specific diagnostic.
- Task 1, Task 2, and Task 3 checkpoints were regenerated from their explicit task boundaries. Task 2 excludes Task 3 files; Task 3 excludes Task 1 and Task 2 implementation files.

### Final Local Test Evidence

All of the following completed with exit code 0:

```bash
find scripts init tests -type f -name '*.sh' -print0 | sort -z | xargs -0 bash -n
bash tests/test-static.sh
bash tests/test-dry-run.sh
bash tests/test-task-3-behavior.sh
shasum -a 256 -c checkpoints/task-01.sha256
shasum -a 256 -c checkpoints/task-02.sha256
shasum -a 256 -c checkpoints/task-03.sha256
git diff --check
```

The local suites cover multi-architecture digest selection, generated MySQL SQL through a stub `mysql`, invalid public-port rejection, incomplete image-resolution rejection, ready-marker ordering, Redis mode `0600` plus UID/GID ownership, Kafka non-root UID/GID configuration, cleanup-trap isolation, and checkpoint boundaries. Test values are explicit fixtures only; no real password was added. No Docker engine command, network request, SSH/SCP operation, image pull, or virtual-machine action was performed.

## Manifest Timeout Increment

### RED

- Added a local-only behavior scenario that executes the generated remote payload with stub `timeout`, stub `docker`, a temporary stack root, and the existing multi-architecture manifest fixture.
- Before implementation, `TEST_CASE=timeout bash tests/test-task-3-behavior.sh` exited 1 with `Probe payload did not move to the second prefix after the first timeout.` The payload called `docker manifest inspect` directly, so the timeout stub was never used and the first prefix was accepted instead of failing over.

### GREEN

- Added `MANIFEST_TIMEOUT_SECONDS="${MANIFEST_TIMEOUT_SECONDS:-20}"` and injected the resolved value into the remote payload. An override test confirms `MANIFEST_TIMEOUT_SECONDS=7` is preserved in generated payload output.
- Every manifest inspection now runs once through GNU `timeout "${MANIFEST_TIMEOUT_SECONDS}s"`. Exit 124 reports the timed-out prefix, reference, and duration; every other non-zero status reports a distinct inspect-failure diagnostic with prefix, reference, and status. Both cases reject the current prefix immediately without retrying it.
- The timeout behavior test passed with only one first-prefix attempt, then recorded second-prefix MySQL through Kafka inspection and `Resolved all images through mirror second.invalid.` Structured digest selection and ready/commit publication assertions remained green.

### Verification

The following local-only commands completed with exit code 0:

```bash
find scripts init tests -type f -name '*.sh' -print0 | sort -z | xargs -0 bash -n
bash tests/test-static.sh
bash tests/test-dry-run.sh
bash tests/test-task-3-behavior.sh
shasum -a 256 -c checkpoints/task-01.sha256
shasum -a 256 -c checkpoints/task-02.sha256
shasum -a 256 -c checkpoints/task-03.sha256
git diff --check
```

No real Docker command, network request, SSH/SCP operation, image pull, or virtual-machine action was performed.
