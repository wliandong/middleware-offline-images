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
