# SHIELD container spike

This directory prototypes a research/calibration workload. It is intentionally
not registered in `models.yml`: SHIELD has no backend model contract yet, and
the spike should establish the right workload abstraction before the monorepo
schema is extended.

The image provides two targets from the same dependency layer:

- `recorded`: baked clean sources, installed exact `jheem2`, offline immutable
  inputs, non-destructive fresh/resume checks, and verified completed outputs;
- `development`: the same dependencies with source-mode `jheem2`; source paths
  can be replaced by bind-mounted worktrees for active development.

Neither target stores input managers or calibration state in the image.

**Team members trying the pilot:** use
[Trying the SHIELD container](https://github.com/tfojo1/jheem_analyses/blob/master/applications/SHIELD/CONTAINER-PILOT.md)
in the analyses repository. No container-repository checkout is needed.
[RUNBOOK.md](RUNBOOK.md) covers administrator installation and maintenance.
The pilot does not yet support a full multi-chain calibration.

## Status (2026-10-01)

- **CI** (`.github/workflows/shield-spike.yml`, validation only): builds the
  recorded image from exact source commits, checks that no team package keeps
  source references, runs preflight offline, runs the kill-and-resume canary,
  completes it through summary and assembly, checks its run records, and runs a
  two-stage pipeline. With image export on, it saves the tested image as an
  artifact. It has no registry login, image push, promotion, or `models.yml`
  integration.
  Main-branch pushes run only the fast shell/contract checks; image builds and
  real-engine canaries run on pull requests or manual dispatch.
- **Team server (shield2, rootless Podman):** the canary calibration runs end to
  end, through summary and assembly, with state on local disk or the NAS
  (101 s, peak 11.1 GB, 5.4 MB checkpoints), and kill-and-resume passes. One
  full `calib.9.28.stage0` run for one location took 27.6 min per 500-iteration
  chunk versus 29.9 min in a native run; different servers, load, and source
  revisions make this a feasibility observation, not a controlled speed or
  scientific-equivalence comparison. It ran before the source-reference fix.
- **Integration:** the opt-in analyses runtime and container pilot are merged
  (`jheem_analyses@3f463e2a`, `jheem-containers@4b9f83db`). The hosted canary at
  [run 36815091235](https://github.com/ncsizemore/jheem-containers/actions/runs/36815091235)
  passed, including missing/modified outputs and changed requested inputs.
- **Image retention:** [shield-pilot-2026.10.01-r36815091235](https://github.com/ncsizemore/jheem-containers/releases/tag/shield-pilot-2026.10.01-r36815091235)
  preserves that run's exact image and archive checksum beyond Actions expiry.
  It is a non-latest pilot prerelease, not a production model promotion.
- **Not yet done:** another team member running it from the runbook, a full
  stage with the fixed image, and multi-chain stage 3 or a tested native handoff.

### Current-source candidate (2026-10-02; not installed)

The October 2 candidate followed the engine used by an October 1 native run and
include its audited ten-line registry correction: removal of an early duplicate
registration that referenced a predecessor before it was defined. Remaining
calibration definitions and likelihood formulas are unchanged. The analyses
candidate also hardens public manager loading after rejected credentials and
adds numerical output inspection. The candidate passed the hosted build,
checkpoint/resume, two-stage canary, numerical output inspection, and negative
output-reuse checks in
[run 37000162439](https://github.com/ncsizemore/jheem-containers/actions/runs/37000162439)
(container source `9d0869d4`, analyses `eab6beb0`). Both downloaded numerical
reports parse as JSON and contain two simulations with 173 finite stored
parameters and finite selected outcomes. Only two transmission parameters vary
in these tiny tests; this is not a full calibration or a native/container
equivalence result. The tested image was exported as an Actions artifact, not
published as a retained release or installed. The retained release and installed
image above have not changed.

Manual CI accepts `input_profile=retained` (the default July 27 syphilis
manager) or `input_profile=native-2026-10-01` (the May 5 manager identified by
digest in that native run's cache, with seed 0). Both select the August 26 census
manager. This is a comparison baseline, not a recommendation to use May data or
a change to manager releases. Matching these inputs does not make the entire
native R/compiler/package environment identical, and retrospective inspection
is not an at-launch record. The canaries remain two-iteration tests, not the
native run's full calibration schedule. The newer `september-2026` profile selects
the intended September 9 manager and seed 0; it leaves the retained default alone.

### Reconciled comparison candidate (2026-10-03; not installed)

The analyses selection now starts from master `4264842c`, which already contains
the registry correction and loader hardening. Only the remaining output inspector
and bounded diagnostic tests were added. No production specification, likelihood,
calibration registration, or loader behavior differs from that master baseline.
The October 2 canary result above does not validate this newer candidate.

Manual validation can opt into `compare_fixed_parameters=true`. This adds two
fresh processes using the **same image**: installed-package engine loading and
the engine's existing hand-sourced loading script. It selects September's manager
for this comparison independently of the canary input profile. No MCMC is started
by this diagnostic; the workflow's separate checkpoint/pipeline canaries still run.

The paired runner mounts identified Git checkouts read-only and checks their
revisions against the image labels. Its native-engine side uses a disposable
analysis copy with one recorded bootstrap substitution: the `pkgload::load_all`
call becomes the existing hand-sourced engine loader. All scientific source stays
identical. The comparator verifies the hashes of that substitution and rejects
any other source difference. This is diagnostic instrumentation, not a new
production loading option or a test of the ordinary native bootstrap in full.

Both processes consume exactly the same parameter doubles through a retained RDS
fixture. For Baltimore, three vectors are scored with the real stage-1 likelihood;
four outcomes are captured annually over 2010–2030 with age/race/sex strata.
Reports preserve 17-significant-digit values, manager digests, source hashes,
runtime information, and the image ID. The comparison describes exact agreement
or absolute/relative differences, including where the largest differences occur.
It does not impose an arbitrary scientific tolerance or claim MCMC replay.

Run the paired diagnostic locally with a built image, clean standalone Git
checkouts at the image's exact refs, and a prepared September cache:

```bash
bash workloads/shield/tests/run_fixed_comparison.sh IMAGE \
  /path/to/jheem_analyses /path/to/jheem2 /path/to/cache /path/to/new-comparison
```

The output path must be new. Reports and logs survive a failed check. CI retains
them in `shield-fixed-comparison` for 14 days; durable evidence must be preserved
before expiry. A passing same-image comparison isolates source/package loading,
not agreement with a team server's native R/compiler/library environment. A
matched native-host comparison and fresh/resumed calibration traces remain later
checks. No release, installed runtime, or running calibration is updated here.

**Local verification, October 3:** the same diagnostic also ran in two fresh
macOS/R 4.4.2 processes, with the engine installed into an isolated library from
the exact source ref above. Installed-package and hand-sourced execution agreed
at full double precision for all 24,948 stratified outcome values, 36 likelihood
components, and three totals. Both used the same September/census bytes and exact
parameter fixture; the scientific-output root remained empty. This validates
the local loading comparison and reporter, not by itself a Linux image pair
or a team server's native environment. The Python tests also confirm that a
single-ULP difference is reported rather than rounded away.

**Hosted comparison, October 3:**
[run 37153878619](https://github.com/ncsizemore/jheem-containers/actions/runs/37153878619)
tested source `eff598ab` with analyses `94ba7298`. The downloaded paired reports
also show exact agreement within the Ubuntu 24.04.1/R 4.4.2 image
`sha256:2819cc3ec51ff7ffaf8804ec82212bcc2fe6248ff02748feb76711830ba924a2`.
The parameter fixture matches the local one byte-for-byte. Linux package versus
Mac hand-sourced execution differs slightly: maximum absolute differences are
about 1.9e-8 per population cell (relative maximum 1.6e-13), 2.1e-10 across the
other three outcomes, and 1.6e-9 in the total log likelihood. These are measured
differences, not an adopted tolerance or a guarantee of identical MCMC traces.
The full records distinguish the BLAS/platform environments; individual causes
of floating-point differences were not isolated. This run does not export an
installable image or update the retained pilot.

### Seed and checkpoint replay comparison

The manual workflow input `compare_calibration_traces` runs four disposable
calibrations in one identified image. Choose `september-2026` to use the current
intended manager input. Each calibration uses Baltimore's real stage-0 likelihood,
samples the two transmission rates, and runs eight iterations across four
two-iteration checkpoints, with no burn-in or thinning.

The experiment compares two fresh processes with the same seed, then a run
interrupted after checkpoints one and two and resumed in separate processes.
A fourth run changes the configured seed by one. The test pauses each interrupted
container and deserializes its checkpoint in a separate read-only process before
stopping it; completed chunk hashes must survive both interruption and resumption.

The report compares original model parameters, initial sampled parameters,
checkpoint seeds, sampled values, likelihood/prior traces, acceptance counts,
and adaptive state at every checkpoint. Values retain full double precision.
It reports the first differing checkpoint and coordinate, excluding timestamps,
runtime durations, and serialized simulation identifiers. A successful changed-seed
control requires different saved seeds and different samples or likelihoods.

For a local built image and a prepared immutable manager cache:

```bash
SHIELD_IMAGE=IMAGE SHIELD_CACHE=/path/to/cache \
  SHIELD_REPLAY_OUTPUT=/path/to/new-replay-output \
  CENSUS_TAG=data-managers-v2026.08.26 \
  SYPHILIS_TAG=syphilis-manager-v2026.09.09 SHIELD_RANDOM_SEED=0 \
  bash workloads/shield/tests/test_repeatability.sh
```

The output path must be new. CI uploads JSON traces, comparison results, logs,
checkpoint verification reports, and run receipts as `shield-repeatability`,
retained for 14 days even if the check fails. Scientific cache/simulation files
remain in the disposable runner state and are not uploaded. Preserve the reports
before expiry. The comparison exits unsuccessfully if either same-seed pair
differs or the changed-seed control has no effect. This experiment characterizes
one short single-chain setup; it does not establish convergence, multi-chain
behavior, cross-platform equality, or the sampler's explicit seed argument.

The [October 3 experiment](https://github.com/ncsizemore/jheem-containers/actions/runs/37161484559)
found exact fresh/fresh agreement and an effective changed-seed control, but
the resumed trajectory first differed at iteration 4. All four runs completed,
and the completed checkpoint files survived both restarts unchanged. The
workflow failed specifically on trace equality, not on operational resumption.
With engine `9578726b` and sampler `4e0d13e`, this optional experiment is therefore
expected to fail on the measured difference; it remains disabled by default.
The [short report and sampler-only reproducer](https://github.com/tfojo1/jheem_analyses/blob/bb93142ecc069e4094e3b130c23109babfb98730/applications/SHIELD/tests/REPLAY-COMPARISON.md)
explain the evidence and extra starting-simulation RNG draw. Neither package,
the installed image, nor active calibrations were changed.

### Actual stage-1 predecessor handoff

The manual input `check_stage1_handoff` runs test-only two-iteration copies of
`calib.10.1.stage0` and `calib.10.1.stage1`. Choose `september-2026` inputs.
Scientific registration fields remain unchanged; test names, predecessor name,
iteration count, burn-in, thinning, and descriptions differ. Both stages use
their actual likelihoods and sampled parameter sets, unlike the older
stage-chaining canary's two uses of stage 0.

The isolated run verifies completed output digests and lineage, the presence of
stage 1's MSM diagnosis likelihood term, exact copying of model parameters from
the predecessor summary, and finite stored samples/likelihoods/priors. It also
inspects the actual simsets and verifies that a completed pipeline is skipped
on a second invocation. Reports and logs are uploaded as `shield-stage1-handoff`
for 14 days, including on failure. Raw science/cache files are not uploaded.

Enable this check when preparing a current-source image for an operator trial.
It runs before image export, so a failed handoff cannot export that candidate.
The result is operational handoff evidence, not convergence, full-stage
performance, stage-2/3 coverage, or exact stochastic replay. No installed image
is replaced by this workflow.

The [October 4 hosted result](https://github.com/ncsizemore/jheem-containers/actions/runs/37203984715)
passed. Stage 0 sampled 88 variables and stage 1 sampled 87; stage 1 used its
twelve registered likelihood terms and copied all 173 predecessor model
parameters exactly. Both stages produced two simulations with verified output
records; repeating the pipeline verified and skipped them. This run did not
export an image. The retained installation is unchanged; a representative
server/operator trial and multi-chain execution remain separate follow-ups.

The full run also passed checkpoint/resume, two-stage assembly, recorded-output
inspection, and rejection of missing/modified outputs and changed requested
seed. Both canary reports contain two simulations, 173 finite parameters, and
finite selected outcomes with September's recorded digest. The second canary
stage still uses the stage-0 likelihood. Successful continuation is not evidence
of uninterrupted/resumed trace equality, which remains a separate test.

## Build from clean local worktrees

The helper verifies that the five source trees are clean and passes their
actual 40-character commits into the image metadata:

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
published merely to perform a local spike. The current candidate defaults are:

- `jheem_analyses`: `94ba72984737d71ea9ca8ed102a8add58b48e6f2`
- `jheem2`: `9578726b012a2ee380b380ef0203733d1bd81163` (October 1 `dev`, including spline fixes)
- `locations`: `2481fc440cf1d981bb1005dd903708a88a528d13`
- `bayesian.simulations`: `4e0d13e85857396bb0e6e2ac1d244775b2145f75` and
  `distributions`: `4d71d9644b4439a59210e804520ac8717ae8f079`, the team servers'
  pins (`jhu-servers` `config/team-packages.txt`)
- base: `ghcr.io/ncsizemore/jheem-base:1.7.0@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3`

The team packages are installed before the SHIELD source is copied, so an image
for a new `jheem_analyses` commit reuses the package layers. They are installed
with `R CMD INSTALL --without-keep.source`. With
kept source references, every simulation saved in a calibration chunk carried
the packages' lazy-load state: about 5.6 GB per stored simulation (305 MB chunk
files) against about 20 MB natively, which also inflated summary and assembly
memory. The build fails if any of these packages keeps source references, and
the canary fails if its first chunk exceeds `SHIELD_MAX_CHUNK_MB` (100 MB).

## Check the image (preflight)

Create a disposable state directory and use an existing manager cache. The
manager tags must identify releases already present in that cache. Preflight
checks the recorded settings and the cached managers' digests without running
the model.

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

`pipeline <location> <calibration-code>...` runs single-chain stages in order
(for example stages 0 to 2), each after the previous one completes, in one
container. It ignores `SHIELD_RUN_MODE`: a stage with verified recorded outputs is
skipped, a stage with a recorded start is resumed, and the rest start fresh, so
running the same pipeline again continues it. It stops at the first failed
stage. Recorded mode refuses multi-chain calibrations (stage 3), because the
monolithic launcher samples chain 1 only.

Before skipping a completed stage, the pipeline verifies both records, actual
output sizes and SHA-256 digests, preceding-stage lineage, and the requested
code, manager identities, and seed. Missing, changed, or stale outputs stop the
pipeline without repairing or clearing scientific state. The hosted test includes
missing and modified simsets and a changed-seed request, not just successful reuse.

## Run records

Each calibration gets `run_records/shield/<location>/<calibration>/` in the
state tree:

- `inputs.json` (written by jheem_analyses when a fresh run starts): the five
  source revisions, the manager releases and SHA-256 digests, the seed, and, for
  a later stage, the SHA-256 of each preceding stage's `outputs.json`. `resume`
  refuses if any of these changed.
- `outputs.json` (written by jheem_analyses once the simulation set is saved):
  the same inputs, and the path, size, and SHA-256 of the MCMC summary and the
  simulation set.
- `attempts/<UTC time>-<mode>.json` (written by this entrypoint): one per fresh
  start or resume, with the image ID, operator, host, settings, start and end
  times, exit status, and the SHA-256 of the two files above when it ended. It
  says `started` until the attempt ends; one left at `started` after its
  container has gone was interrupted. `shield-run.sh` passes the image ID,
  operator, and host; a bare `docker run` records them as `unknown` unless
  `SHIELD_IMAGE_ID`, `SHIELD_OPERATOR`, and `SHIELD_HOST` are set.

This is a first version for gathering real records; the schema may change.

## What CI proves, and what it doesn't

The hosted canary (`tests/test_checkpoint_resume.sh`) runs `container.smoke.stage0`
(enabled by `SHIELD_ENABLE_CONTAINER_SMOKE=true`): the real SHIELD model and
stage-0 likelihood, two iterations, a checkpoint after each. It proves that the
image builds from its pinned sources, preflight verifies the recorded settings
and manager digests, a fresh run writes a durable checkpoint and survives
SIGKILL, and a separate resumed process continues from that checkpoint without
rewriting it and writes the next one.

It stops the resumed run once that second checkpoint is durable. A third
process then resumes it to completion through the MCMC summary and assembly
(`tests/test_records_and_pipeline.sh`), and CI checks the run records: three
attempts (two interrupted, one succeeded), and an `outputs.json` whose sizes and
digests match the files. `pipeline` then skips that completed stage and runs
`container.smoke.stage1` from it, whose inputs must name stage 0's
`outputs.json` digest; running the pipeline again must change nothing. CI does
not cover production-sized stages, or server storage, ownership, and
concurrency. Before the source-reference fix, building the summary exceeded the
16 GB hosted runner's memory (run 36593697214); with the fix the full canary
peaks at about 11 GB on shield2.

The candidate also loads each completed canary simset and checks its identity,
simulation count, finite named parameters, and selected yearly outcomes. It
writes `diagnostics/numeric-container.smoke.stage*.json` with actual parameter
and outcome values (up to five simulations) plus descriptive ranges. Missing or
non-finite selected results fail; negative outcome counts remain visible. The
inspector and its focused unit tests live in `jheem_analyses` alongside the
recorded runtime. These reports are not convergence tests or native/container
equivalence results.

The next numerical comparison should evaluate the same saved parameter vector
with matched scientific source and manager bytes in both environments, then
compare trajectories and each likelihood contribution. Only after that should
full calibration summaries be compared. Exact equality of independent MCMC
traces or serialized simset bytes is not the current acceptance criterion.

The server pilot covers the rest: the canary through summary and assembly,
one realistic stage, and NAS mounts, ownership, and output locations (all done
on shield2), and another team member operating it from the analyses operator guide
(not yet done).

A green CI run means the container contract holds, not that SHIELD
calibrations work end to end on a server.

### Running the pilot on a team server

The team servers run RHEL 9 with rootless Podman and SELinux enforcing. Run the
`shield-spike` workflow with image export on (the manual `export_image` input,
or the `export-image` label on a pull request), download its
`shield-recorded-image` artifact, check it against `IMAGE.txt`, and load it.
To follow the team's code, a manual run can build another `jheem_analyses`
commit with the `jheem_analyses_ref` input (a full SHA that includes the
recorded runtime); it reuses the package layers, and `IMAGE.txt` names the
commit.

```bash
gh workflow run shield-spike.yml --repo ncsizemore/jheem-containers \
  --ref <branch> -f export_image=true -f jheem_analyses_ref=<40-character SHA>
```

Add `-f input_profile=native-2026-10-01` for the identified May-manager
comparison. `IMAGE.txt` records the selected profile, tags, seed, and engine
revision. The input-preparation helper accepts the same profile:

```bash
python3 workloads/shield/tests/prepare_inputs.py /path/to/comparison-cache \
  --profile native-2026-10-01
```

Outside CI, set the corresponding tags and `SHIELD_RANDOM_SEED=0` explicitly
when running that comparison; preparing a cache does not change runtime settings.

Then:

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

`pilot_full_run.sh` records exit status, elapsed time, peak memory, chunk
timings, and whether the summary and simulation set were written, in
`<state>/pilot-full-run/`; set `SHIELD_CALIBRATION` and `SHIELD_LOCATION` to run a
real stage. For the pilot, `shield-run.sh` wraps these settings; see the analyses
operator guide linked above. Administrator preparation is in [RUNBOOK.md](RUNBOOK.md).

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

Uncommitted development work is permitted. This is not a recorded run: its
source and inputs are not identified or checked.

## What this spike does not yet prove

- Runtime has been validated on shield2 (rootless Podman) and in CI (Docker),
  not on shield1, shield3, or a developer machine.
- CI and the runbook use exact census and syphilis manager releases and digests;
  the team still chooses which releases a real calibration should use. The
  defaults are `data-managers-v2026.08.26` and `syphilis-manager-v2026.07.27`,
  the release current SHIELD source pins, rather than the newest release.
- The source overlay is reproducible, but its package installs (the four team
  packages and `filelock`) are not yet represented by a standalone SHIELD
  lockfile. That should be resolved before promoting a recorded environment.
- The local build helper verifies clean commits immediately before BuildKit
  snapshots each directory, but it is not a release-grade content handoff.
  Published recorded images should consume immutable Git contexts or verified
  source archives to eliminate that check/copy race.
- SHIELD state and final outputs still share `JHEEM_ROOT_DIR` because the model
  engine currently owns that layout. They should not be claimed as separate
  mounts until the source contract actually supports it.
- A cross-process calibration lock is not implemented. `shield-run.sh` refuses
  a second run of a calibration that one of your own containers is running;
  across accounts, operators must still prevent duplicate writers for the same
  location, calibration code, and chain.
- Stage 3 (four parallel chains and assembly) isn't supported in recorded mode.
- The image bakes one `jheem_analyses` commit, so a calibration registered after
  that commit is unavailable through the bare image entrypoint. The operator
  wrapper can instead capture a clean committed analysis checkout and mount
  the preserved snapshot read-only, without rebuilding the image. See the
  [source selection reference](SOURCE-SNAPSHOTS.md).

Run the spike's static contract tests with:

```bash
pytest workloads/shield/tests/test_contract.py -q
```
