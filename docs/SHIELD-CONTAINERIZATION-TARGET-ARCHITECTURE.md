# SHIELD Containerization Target Architecture

**Status:** target architecture; Phase 0 implemented on an isolated source branch; Phase 1 spike in progress

**Date:** 2026-09-16

**Scope:** active SHIELD development and calibration workloads

## Implementation checkpoint

The first implementation pass is intentionally split across repositories:

- `jheem_analyses` canonical staging branch `codex/shield-source-readiness` at
  `accd7b64dd0ab1f38f5ccad993a643c3c7544de2` implements the Phase 0 runtime,
  provenance, retry/resume, path, engine-test, and immutable census/syphilis
  manager changes. Verified offline managers can be consumed from a read-only
  cache without attempting a writer lock. The branch also removes SHIELD's
  unused Google-mobility cache load. It is based on the current upstream
  `master`. It is published for repeatable testing but is not approved or
  scheduled for merge to `master`.
- `jheem2` is currently evaluated at
  `90b68ad500c12bdfe8f9dc6616e9a846fb4ae3d1` (version `1.12.3.9000`).
- `locations` is overlaid at
  `2481fc440cf1d981bb1005dd903708a88a528d13` (version `0.5.0.9000`) because
  SHIELD requires the newer Oakland TGA definitions than the shared base
  currently provides.
- `workloads/shield/` contains the initial development/recorded image spike.
  It is deliberately outside `models.yml` until the workload contract is
  demonstrated rather than guessed.

Both package-mode and source-mode source-level integration tests now load the
real cached managers, construct the SHIELD engine, run one median-parameter
simulation through 2030, and assert a finite population outcome. This is
evidence of source readiness. The recorded image also builds successfully on a
clean GitHub Linux/amd64 runner; the PR workflow now loads the ephemeral image
and exercises preflight and the real engine with pinned inputs and networking
disabled. A real two-iteration MCMC canary has also demonstrated finite initial
likelihood, durable checkpointing across forced termination, selective resume,
and summary generation. Final simulation-set assembly exceeded hosted-runner
memory even at two simulations and remains a SHIELD-server acceptance test.

## Summary

Containerizing SHIELD is a sound way to reduce machine-specific R, package, compiler, BLAS, and operating-
system drift. SHIELD should not initially be modeled as another deployed portal container, however. It is an
active research and calibration workload with editable source, controlled inputs, multi-process execution,
large persistent checkpoints, and explicit resume requirements.

The target is therefore:

```text
pinned dependency environment
  + explicit source identity
  + external immutable inputs
  + external persistent calibration state
  + resource-bounded execution
  + run provenance
```

An image is one part of that contract. It is not the owner of calibration state, source control, server
scheduling, or data-access policy.

## Why the existing portal-image pattern is insufficient

| Concern | Existing portal model images | SHIELD calibration |
| --- | --- | --- |
| Source lifecycle | frozen release refs | actively edited across repositories |
| Primary execution | individual simulations and artifact extraction | cities x stages x MCMC chains |
| State | mostly per-run/transient | large, long-lived checkpoints that must resume |
| Inputs | published simsets and serialized workspaces | versioned managers plus shared research inputs |
| Validation | reviewed golden-output regression | engine invariants, checkpoint/resume, and calibration canaries |
| Release cadence | portal-facing image releases | deliberate research-environment releases |

The current `models.yml` contract also assumes a deployed backend model. SHIELD should not acquire a fake
`backend_model_id` merely to satisfy that schema.

## Architectural decisions

### 1. Separate development and recorded-run targets

The implementation should provide two related targets built from the same dependency definition:

- **Development target:** supports bind-mounted `jheem_analyses` and `jheem2` source for interactive work.
  It records the commit and dirty-tree state, but dirty runs are not considered fully reproducible.
- **Recorded-run target:** bakes exact source commits into an immutable image. It performs no `git pull`,
  branch checkout, or reset at startup. Official calibration results use this target and a clean source
  identity.

An optional RStudio-facing profile can be evaluated after the batch/development-shell workflow succeeds.
Running and securing a per-user RStudio Server inside a container is not required for the first spike.

### 2. Keep data and state outside the image

The runtime contract should use explicit mounts or equivalent managed volumes:

| Path role | Access | Purpose |
| --- | --- | --- |
| source override | read/write in development only | actively edited model source |
| immutable inputs | read-only | selected data-manager releases and other fixed inputs |
| input cache | read/write | verified downloads that may be reused between runs |
| calibration state | read/write | MCMC checkpoints and chain controls |
| outputs | read/write | assembled simsets, receipts, summaries, and logs |

Credentials remain runtime secrets and are never copied into image layers. Data-manager selection must use
an explicit immutable release identity and digest for recorded runs.

### 3. Replace machine inference with explicit configuration

Container execution must not infer storage from hostnames such as `shield1` or paths such as `Q:` and
`/Volumes/jheem$`. Root, cache, state, and output paths must be supplied explicitly and validated at startup.

A versioned run specification should capture at least:

- image digest and source revisions;
- location and calibration code;
- stage and chain count;
- random seed policy;
- selected data-manager releases and digests;
- fresh-versus-resume behavior;
- CPU, memory, and BLAS thread settings;
- incomplete-assembly policy;
- output and checkpoint locations.

### 4. Make failure and resume semantics explicit

Before containerization is treated as production-ready, the SHIELD runner should:

- distinguish transient storage failures from deterministic model errors;
- exit nonzero when retries are exhausted;
- preserve the original error in logs and provenance;
- make destructive cache clearing opt-in;
- make incomplete assembly opt-in;
- use unique run identifiers and non-overwriting logs;
- prevent two launchers from silently controlling the same location/calibration cache;
- handle termination so that a stopped container can safely resume from the last valid checkpoint.

### 5. Use a research/calibration workload contract

The existing deployed-model schema should not be generalized prematurely. After a successful spike, the
container manifest can add a versioned workload kind such as `research-calibration`, with backend integration
optional rather than required.

That workload should own:

- image name and build context;
- exact source refs for `jheem_analyses`, `jheem2`, and other in-house packages;
- R and system dependency identity;
- supported entrypoints;
- mount and resource contracts;
- fast and canary tests;
- explicit promotion policy.

Whether this is represented as a new top-level manifest section or a schema-v2 `images` collection should be
decided after the spike demonstrates the common and differing fields. The first Dockerfile should not force
that abstraction decision.

### 6. Use deliberate release semantics

SHIELD candidates should be published by commit/digest for testing. Approved calibration environments should
receive explicit version tags. A merge to `main` should not automatically advance a SHIELD `latest` tag.

## Verification strategy

Fast pull-request checks should cover:

- image build and package/source identity;
- loading the SHIELD specification;
- one small deterministic engine run;
- finite likelihood evaluation;
- creation of a tiny checkpoint;
- termination and resume from that checkpoint;
- correct nonzero exit behavior for a forced deterministic failure;
- provenance receipt fields and mount-permission checks.

A scheduled or manual canary on a SHIELD server should exercise the real container runtime, NAS mount, UID/GID
mapping, SELinux behavior, and a bounded calibration. Full scientific calibration is not a pull-request test.

## Phased implementation

### Phase 0: source readiness

1. **Implemented on the canonical staging branch:** reconcile active `jheem_analyses` work with upstream,
   including provenance changes.
2. **Implemented:** remove runtime Git mutation from model initialization.
3. **Partially implemented:** introduce explicit root/cache configuration. State and final outputs still
   share the engine's `JHEEM_ROOT_DIR` layout and must not yet be represented as separate mounts.
4. **Implemented:** correct retry, exit-status, resume, and incomplete-assembly behavior.
5. **Implemented and run locally:** establish a small automated SHIELD engine test independent of the
   container, in both package and source modes.

### Phase 1: container spike

1. **Source and CI image build complete; runtime test added:** evaluate the required R version against the
   exact active `jheem2` and `jheem_analyses` revisions.
2. **In progress:** create minimal development/recorded-run targets. The shared base is digest-pinned and
   source revisions are exact; the SHIELD-specific dependency overlay still needs a standalone lockfile.
3. **Implemented in CI:** run the deterministic engine plus an opt-in,
   two-iteration calibration canary that is killed after one durable chunk and
   resumes only the remaining chunk. Final assembly remains server-only because
   the full simulation objects exceed hosted-runner memory.
4. Pilot rootless Podman or Docker on `shield3` using the actual NAS and shared-group permissions.
5. Benchmark host versus container behavior and verify checkpoint/resume after forced termination.

### Phase 2: monorepo integration

1. Add the research/calibration workload schema and structural contracts.
2. Add build -> test-by-digest promotion using explicit SHIELD release tags.
3. Add the server canary path without placing controlled inputs in GitHub-hosted CI.
4. Document the researcher workflow and support boundary.

### Phase 3: team adoption

1. Have multiple researchers reproduce the same bounded run.
2. Add the optional interactive/RStudio workflow if needed.
3. Migrate real calibration work incrementally, retaining the host workflow until resume and performance are
   proven under realistic load.

## Deferred and independent questions

The contents and redistribution status of data managers embedded in existing published images should be
reviewed separately. This document does not assert that the current publication is improper, and that review
does not block the SHIELD architecture planning described here. SHIELD should nevertheless adopt an explicit
input/mount policy so its own image boundary is unambiguous.

## Exit criteria for the spike

Do not proceed to schema integration or team rollout until all of the following are demonstrated:

- the same clean source identity runs on a developer machine and a SHIELD server;
- a bounded result is scientifically equivalent within an agreed tolerance;
- checkpoint/resume survives forced termination;
- deterministic failures exit nonzero without prolonged retry loops;
- the container writes NAS state under the intended host user/group;
- the resulting receipt identifies the image, source, inputs, run configuration, and output digest.
