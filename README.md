# jheem-containers

Canonical monorepo for the JHEEM model container system: the shared R base image plus the per-model
images that reproduce published JHEEM analyses and power custom simulations on
[jheem.org](https://jheem.org).

This repo consolidates the former per-image container repositories into one history-preserving build and
release surface. Its main job is to make JHEEM containers reproducible, testable, and safe to promote
without rebuilding untested artifacts.

## Current status

Implemented:

- History-preserving migration from the former per-image repositories.
- Path-aware CI selection for affected images in pull requests.
- Build -> test-by-digest -> promote workflow for model images.
- Full pull-request validation for affected images: smoke tests, golden regression tests, and targeted
  perturbation tests.
- Fail-closed promotion to `latest` and semver tags: CI re-tags the exact digest that passed tests instead
  of rebuilding for release.
- Retry/resume/verify for large simulation-set downloads and an **authenticated** release-API query
  (`jheem-base:1.6.5`, via `GITHUB_TOKEN`), so transient blips and API rate limits don't fail a run.

Still open:

- Base-image candidate compatibility cascade. The current gate validates model-image candidates; it does
  not yet prove that a candidate base image is compatible with every downstream model before promotion.
- ~~Canonical model configuration~~ **done**: `models.yml` owns container build/test/provenance metadata;
  a dedicated CI `contract` job validates the Dockerfiles, registry digests, and backend-shared fields
  (param `id -> envVar` maps, scripts, image names, simset releases) against it on every PR, the test
  suite reads it directly, and the build matrix is generated from it. Backend `models.json` remains
  authoritative for application/runtime/product configuration. See
  [`docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md`](docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md).
- Runtime-contract cleanup. Lambda and batch modes work, but the entrypoint contract should be made
  simpler and more explicit.
- Provenance hardening. Images expose useful version metadata, but the release metadata should eventually
  include a stronger audited chain from source refs to promoted digests.

In short: this is a credible model-image promotion gate, not yet a complete base-plus-model release
framework.

## Repository structure

| Path | Purpose |
| --- | --- |
| `base/` | Shared R runtime, model-agnostic scripts, simulation-set fetch tooling, and the custom-simulation orchestrator. |
| `models/` | One directory per model image, each built from `ghcr.io/ncsizemore/jheem-base`. |
| `tests/` | CI/local tests for smoke checks, golden-output regression, and perturbation behavior. |
| `docs/` | Migration notes, independent reviews, and responses tracking the release-system design. |

## Images

Images publish to GitHub Container Registry under `ghcr.io/ncsizemore`.

Models are driven via `custom` (backend pipeline) or `run` (standalone); a bare `docker run` prints
`version`.

| Context | Image | Current base | Gate coverage |
| --- | --- | --- | --- |
| `base/` | `jheem-base` | n/a (shared runtime) | Build/publish; downstream cascade still open |
| `models/ryan-white-msa/` | `jheem-ryan-white-msa` | `1.6.5` | Smoke + golden + perturbation |
| `models/ryan-white-ajph/` | `jheem-ryan-white-ajph` | `1.6.5` | Smoke + golden + perturbation |
| `models/ryan-white-croi/` | `jheem-ryan-white-croi` | `1.6.5` | Smoke + golden + perturbation |
| `models/cdc-testing/` | `jheem-cdc-testing` | `1.6.5` | Smoke + golden + perturbation |

All model images build on a single base version (`jheem-base:1.6.5`), pinned by digest.

## CI and promotion model

The release workflow is designed around immutable image digests:

1. Build each selected candidate image and push it under a temporary `gate-<sha>` tag.
2. Record the candidate digest as an artifact.
3. Pull and test that exact digest.
4. Promote only the tested digest by re-tagging it as `latest` or a semver release tag.

Promotion behavior:

| Trigger | What runs | Promotion |
| --- | --- | --- |
| Pull request | Full smoke + slow tests for affected images | No promotion |
| Push to `main` | Full test suite | Promote tested digests to `latest` |
| Tag `<image>-vX.Y.Z` | Full test suite for the tagged image | Promote tested digest to `X.Y.Z` and `X.Y` |
| Manual workflow dispatch | Full test suite | No promotion |

This prevents the common failure mode where CI tests one image but publishes another.

## Local testing

Fast smoke tests:

```bash
pytest tests/test_smoke.py
```

Full regression and perturbation tests:

```bash
pytest tests/test_golden.py
```

The slow tests compare model outputs against checked-in golden artifacts under each model directory.
They are intended to catch runtime regressions, missing scenario outputs, duplicate keys, null/value
changes, and role-breakdown drift.

## Related JHEEM repositories

- [`jheem-backend`](https://github.com/ncsizemore/jheem-backend) consumes promoted image tags and launches
  custom simulations.
- [`jheem-portal`](https://github.com/ncsizemore/jheem-portal) is the public web interface.
- [`jheem-simulations`](https://github.com/ncsizemore/jheem-simulations) stores simulation artifacts and
  release data used by the portal.

Legacy per-image repositories should remain available until historical tags and any external references
have been recovered or intentionally retired.
