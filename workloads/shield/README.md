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
- The five spike contract tests and shell/R parse checks pass.
- `.github/workflows/shield-spike.yml` provides a PR-triggered, Linux/amd64,
  validation-only build from the exact canonical source commits. The first
  live run built the recorded image successfully in 5m14s. The workflow
  loads that image only into its ephemeral runner, materializes two
  digest-pinned public manager releases, and runs preflight with networking
  disabled. That earlier spike (older analyses source and jheem2) also
  completed a summary. Since 2026-09-29 the image builds from the recorded-run
  source; its canary stops at the resumed checkpoint, as described under
  "What CI proves" below. It has no registry login, write permission, image
  push, promotion, or `models.yml` integration.
- Docker Desktop on the development workstation still stalls resolving the
  pinned base through its configured registry proxy. That local proxy issue is
  not on the critical path now that the same image definition builds on a clean
  GitHub Linux/amd64 runner.

## Build from clean local worktrees

The helper verifies that both source trees are clean and passes their actual
40-character commits into the image metadata:

```bash
workloads/shield/build-local.sh \
  /path/to/jheem_analyses \
  /path/to/jheem2 \
  /path/to/locations \
  /path/to/bayesian.simulations \
  /path/to/distributions \
  recorded
```

This uses BuildKit named contexts, so the source repositories do not need to be
published merely to perform a local spike. The current reviewed defaults are:

- `jheem_analyses`: `e0580817212079fec1cb249f424bf5df9cfbeb3f` (branch `codex/shield-recorded-contract`)
- `jheem2`: `ccb1f9bfe40844143dbcec65ffd27829aa39d7ef` (`dev`)
- `locations`: `2481fc440cf1d981bb1005dd903708a88a528d13`
- `bayesian.simulations`: `4e0d13e85857396bb0e6e2ac1d244775b2145f75` and
  `distributions`: `4d71d9644b4439a59210e804520ac8717ae8f079`, the team servers'
  pins (`jhu-servers` `config/team-packages.txt`)

The team packages are installed with `R CMD INSTALL --without-keep.source`. With
kept source references, every simulation saved in a calibration chunk carried
the packages' lazy-load state: about 5.6 GB per stored simulation (305 MB chunk
files) against about 20 MB natively, which also inflated summary and assembly
memory. The build fails if any of these packages keeps source references, and
the canary fails if its first chunk exceeds `SHIELD_MAX_CHUNK_MB` (100 MB).
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
  --env JHEEM_CENSUS_MANAGER_TAG=data-managers-v2026.08.26 \
  --env JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-vYYYY.MM.DD \
  --env SHIELD_RANDOM_SEED=20260916 \
  jheem-shield:recorded \
  preflight
```

Do not weaken recorded mode merely to accommodate an unversioned manager. Use
the development target while preparing or validating a release instead.

## Run or resume calibration

The recorded image runs the monolithic SHIELD launcher in recorded mode (see
`applications/SHIELD/RECORDED-RUN-PILOT.md` in `jheem_analyses`). `fresh` sets
up and starts a new calibration and refuses to replace existing state; it never
clears a cache. `resume` (the default) continues from the last checkpoint and
fails if there is none or if the recorded inputs changed:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,src=/path/to/cached,dst=/work/cache,readonly \
  --mount type=bind,src=/path/to/shield-state,dst=/work/state \
  --env JHEEM_CENSUS_MANAGER_TAG=data-managers-v2026.08.26 \
  --env JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-vYYYY.MM.DD \
  --env SHIELD_RANDOM_SEED=20260916 \
  --env SHIELD_RUN_MODE=fresh \
  jheem-shield:recorded \
  calibrate C.12580 <calibration-code>
```

For continuation, use the same state mount and identifiers with
`SHIELD_RUN_MODE=resume`. The entrypoint refuses root by default so NAS files
are not silently created under the wrong ownership.

## What CI proves, and what it doesn't

The hosted canary (`tests/test_checkpoint_resume.sh`) runs `container.smoke.stage0`
(enabled by `SHIELD_ENABLE_CONTAINER_SMOKE=true`): the real SHIELD model and
stage-0 likelihood, two iterations, a checkpoint after each. It proves that the
image builds from its pinned sources, preflight verifies the recorded settings
and manager digests, a fresh run writes a durable checkpoint and survives
SIGKILL, and a separate resumed process continues from that checkpoint without
rewriting it and writes the next one.

It stops the resumed run once that second checkpoint is durable. It does **not**
cover the MCMC summary, simulation-set assembly, production-sized stages, or
server storage, ownership, and concurrency. On the 16 GB hosted runner SHIELD
uses about 9 GB to load and sample and exceeds the runner's memory while
building the summary (run 36593697214). Those steps belong to the server pilot:

1. Run the same canary calibration on a team server without interruption
   through summary and assembly, recording peak memory.
2. Run one realistic stage for one location and compare runtime with the
   ordinary launcher.
3. Check NAS mounts, file ownership, and output locations.
4. Have another team member launch, interrupt, and resume from this README.

A green CI run means the container contract holds, not that SHIELD
calibrations work end to end on a server.

### Running the pilot on a team server

The team servers run RHEL 9 with rootless Podman and SELinux enforcing. Run the
`shield-spike` workflow with image export on (the manual `export_image` input,
or the `export-image` label on a pull request), download its
`shield-recorded-image` artifact, check it against `IMAGE.txt`, and load it:

```bash
sha256sum -c <(grep jheem-shield-recorded.tar.gz IMAGE.txt)
podman load -i jheem-shield-recorded.tar.gz
python3 tests/prepare_inputs.py ~/shield-pilot/cache
```

Both scripts take `CONTAINER_ENGINE=podman` (rootless runs use
`--userns=keep-id`, so files keep your ownership); `tests/engine-env.sh` holds
the shared settings. `SHIELD_MOUNT_RELABEL=shared` relabels local directories
for SELinux and is skipped automatically for CIFS paths such as the NAS, which
can't be relabeled. For state on the NAS:

- an administrator enables the `virt_use_samba` SELinux boolean on the host;
- set `SHIELD_KEEP_GROUPS=true`, so the container keeps your `jheem` group and
  can write to the group-writable share;
- enable lingering for the user (`loginctl enable-linger <user>`), or rootless
  containers are stopped about 10 seconds after that user's last login session
  ends.

```bash
export CONTAINER_ENGINE=podman SHIELD_MOUNT_RELABEL=shared \
  SHIELD_IMAGE=docker.io/library/jheem-shield:ci SHIELD_CACHE=~/shield-pilot/cache \
  CENSUS_TAG=data-managers-v2026.08.26 SYPHILIS_TAG=syphilis-manager-v2026.07.27

SHIELD_STATE=~/shield-pilot/full bash tests/pilot_full_run.sh        # summary and assembly
SHIELD_STATE=~/shield-pilot/resume bash tests/test_checkpoint_resume.sh
```

`pilot_full_run.sh` records exit status, elapsed time, peak memory, and whether
the summary and simulation set were written, in `<state>/pilot-full-run/`.

## Development source overrides

Build the `development` target and mount both worktrees. It runs the ordinary
(non-recorded) SHIELD path against the mounted source:

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
  jheem-shield:development \
  shell
```

Dirty development work is permitted and is recorded as modified. It is not a
fully reproducible recorded run.

## What this spike does not yet prove

- The image has passed a real Linux/amd64 CI build, but not yet a complete
  Docker/Podman runtime validation on a developer machine or `shield3`.
- CI uses exact census and syphilis manager releases and digests; the team must
  still select the manager releases for the first retained pilot calibration.
  The canary uses `syphilis-manager-v2026.07.27`, the release current SHIELD
  source pins, rather than silently following the newest release.
- NAS UID/GID/SELinux behavior, host-versus-container performance, the MCMC
  summary, and simulation-set assembly remain server acceptance tests. With the
  pinned jheem2, building the summary alone exceeds the hosted runner's memory,
  so CI stops at the resumed checkpoint (see "What CI proves" above).
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
