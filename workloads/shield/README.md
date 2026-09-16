# SHIELD container spike

This directory prototypes a research/calibration workload. It is intentionally
not registered in `models.yml`: SHIELD has no backend model contract yet, and
the spike should establish the right workload abstraction before the monorepo
schema is extended.

The image provides two targets from the same dependency layer:

- `recorded`: baked clean sources, installed exact `jheem2`, offline immutable
  inputs, resume by default, and no incomplete assembly;
- `development`: the same dependencies with source-mode `jheem2`; source paths
  can be replaced by bind-mounted worktrees for active development.

Neither target stores input managers or calibration state in the image.

## Validation status (2026-09-16)

- Source-level SHIELD integration passes with the pinned revisions in both
  installed-package and source-loading modes. Each run constructs the real
  engine and produces finite population output through 2030.
- The three spike contract tests and shell/R parse checks pass.
- The first Docker build accepted the Dockerfile and both named source
  contexts, then stalled resolving the pinned base through this workstation's
  Docker Desktop registry proxy. A direct pull stalled at the same point even
  though host-side GHCR access and anonymous-token issuance succeeded. No
  completed image build or container test is claimed yet.

## Build from clean local worktrees

The helper verifies that both source trees are clean and passes their actual
40-character commits into the image metadata:

```bash
workloads/shield/build-local.sh \
  /path/to/jheem_analyses \
  /path/to/jheem2 \
  recorded
```

This uses BuildKit named contexts, so the source repositories do not need to be
published merely to perform a local spike. The current reviewed defaults are:

- `jheem_analyses`: `31df932a292b784823ce36ebd1937e39f547163b`
- `jheem2`: `90b68ad500c12bdfe8f9dc6616e9a846fb4ae3d1`
- base: `ghcr.io/ncsizemore/jheem-base:1.7.0@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3`

## Run the engine integration test

Create a disposable state directory and use an existing manager cache. The
syphilis manager tag must identify a release already present in that cache.

```bash
mkdir -p /path/to/shield-state

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,src=/path/to/cached,dst=/work/cache,readonly \
  --mount type=bind,src=/path/to/shield-state,dst=/work/state \
  --env JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-vYYYY.MM.DD \
  jheem-shield:recorded-31df932a292b \
  engine-test
```

Do not weaken recorded mode merely to accommodate an unversioned manager. Use
the development target while preparing or validating a release instead.

## Run or resume calibration

Fresh setup is explicit and destructive for the selected location/code:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,src=/path/to/cached,dst=/work/cache,readonly \
  --mount type=bind,src=/path/to/shield-state,dst=/work/state \
  --env JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-vYYYY.MM.DD \
  --env SHIELD_RUN_ID=my-unique-run-id \
  --env SHIELD_RUN_MODE=fresh \
  jheem-shield:recorded-31df932a292b \
  calibration-stage C.12580 shield_calibration_stage all 1
```

For continuation, use the same state mount and identifiers with
`SHIELD_RUN_MODE=resume`. The default is resume and it fails when no checkpoint
exists. The entrypoint refuses root by default so NAS files are not silently
created under the wrong ownership.

## Development source overrides

Build the `development` target, mount both worktrees, and clear the baked source
declarations so provenance inspects their Git state directly:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,src=/path/to/jheem_analyses,dst=/workspace/jheem_analyses \
  --mount type=bind,src=/path/to/jheem2,dst=/workspace/jheem2 \
  --mount type=bind,src=/path/to/cached,dst=/work/cache,readonly \
  --mount type=bind,src=/path/to/shield-state,dst=/work/state \
  --env JHEEM_ANALYSES_PATH=/workspace/jheem_analyses \
  --env JHEEM2_PATH=/workspace/jheem2 \
  --env JHEEM_ANALYSES_REF= \
  --env JHEEM2_REF= \
  jheem-shield:development-31df932a292b \
  shell
```

Dirty development work is permitted and is recorded as modified. It is not a
fully reproducible recorded run.

## What this spike does not yet prove

- The image has not yet passed the real Docker/Podman build on both a developer
  machine and `shield3`.
- The exact immutable manager tag and digest for the pilot still need to be
  selected.
- Tiny calibration, forced termination/resume, finite likelihood, NAS
  UID/GID/SELinux behavior, and host-versus-container performance remain live
  acceptance tests.
- The source overlay is reproducible, but its two delta installs are not yet
  represented by a standalone SHIELD lockfile. That should be resolved before
  promoting a recorded environment.
- The local build helper verifies clean commits immediately before BuildKit
  snapshots each directory, but it is not a release-grade content handoff.
  Published recorded images should consume immutable Git contexts or verified
  source archives to eliminate that check/copy race.
- SHIELD state and final outputs still share `JHEEM_ROOT_DIR` because the model
  engine currently owns that layout. They should not be claimed as separate
  mounts until the source contract actually supports it.
- A cross-process calibration lock is not implemented. Until chain-aware
  locking is designed, the scheduler/operator must prevent duplicate writers
  for the same location, calibration code, and chain.

Run the spike's static contract tests with:

```bash
pytest workloads/shield/tests/test_contract.py -q
```
