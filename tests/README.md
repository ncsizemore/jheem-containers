# Container promotion-gate test suite

The test layer of the build → **test-by-digest** → promote gate (per the independent
review). It tests an *exact candidate image*, never a rebuild between testing and
promotion.

## Layers

**Contract (repo-state; the CI `contract` job — always runs, even when no image builds):**

- **`test_models_yml.py`** — Dockerfiles agree with the canonical `models.yml`; global
  coverage checks (every model dir has a manifest entry — catches a PR adding
  `models/new-model/` without one, which selects an empty matrix).
- **`test_base_pin.py`** — the pinned base digest matches what the registry serves.
- **`test_cross_repo.py`** — backend-shared fields agree with backend `models.json`
  (param `id -> envVar`, scripts, image names, simset releases + reverse coverage).

These get their own job because the matrix jobs' `-k <model>` deselects the global
(non-parametrized) tests — a hole an independent review caught.

**Candidate-image behavior (the matrix `test` jobs, per selected model):**

- **`test_smoke.py`** (fast, no simulation) — image `version`/provenance fields, and
  `test-workspace` loading the model's specification object. Cheap enough to gate every build.
- **`test_golden.py`** (`slow`, runs the simulation) —
  - **regression:** a fixed scenario reproduces the committed reviewed golden `0.0`;
  - **perturbation:** a *non-default* parameter moves the intervention while baseline is
    unchanged — proving each parameter reaches the model. This is what catches the CDC
    env-var-name class of bug (a default-valued golden silently passed it).

`golden_compare.py` is the comparator: multi-slice, **null-vs-value is a mismatch**,
**duplicate keys fail**, per-role (baseline/intervention) breakdown. It accepts either the
full production custom-simulation artifact or a focused slim `run` artifact. For an
intentional contract change, keep the former in place as `reference_artifact` and add a
new reviewed artifact as the active regression gate.

## Running

```bash
pip install -r tests/requirements.txt
# fast tier only:
pytest tests -m "not slow"
# everything (downloads simsets, runs sims — gate/nightly):
pytest tests
# one model:
pytest tests -k cdc-testing
```

By default it tests `ghcr.io/<owner>/<image>:latest`. The gate overrides per model with
the candidate digest via `GATE_IMAGE_<MODEL>=…@sha256:…` so it tests exactly what will
be promoted.

## Config

The suite reads the canonical [`models.yml`](../models.yml) directly (`conftest.config()`)
— per-model image, golden scenario, perturbation, spec object, base version. There is no
separate test config to keep in sync (the old hand-maintained `test_config.json` was
deleted rather than generated). To change what the gate tests, edit `models.yml`.

`models.yml` is scoped to container build/test/provenance metadata. Backend
`models.json` remains authoritative for application/runtime/product configuration, and
shared fields should be checked by CI. See
[`docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md`](../docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md).

For coordinated pull requests, CI first checks the backend branch matching the
container pull request's branch name and falls back to backend `master` when no
matching branch exists. Local coordinated work can set
`BACKEND_MODELS_PATH=/path/to/jheem-backend/.github/config/models.json`.

## When the gate runs (merge / release policy)

| Event | Builds | Tests | Promotes |
|-------|--------|-------|----------|
| model `pull_request` → main | affected models (`select`) | contract + **full** behavior (smoke + slow) | no |
| base `pull_request` → main | candidate base + every model built from its digest | base contract + every model's **full** behavior | no |
| model push → `main` | affected models | **full** | `:latest` (fail-closed) |
| base push → `main` | candidate base + all downstream models | **full cascade** | no; explicit release tag required |
| tag `base-vX.Y.Z` | candidate base + all downstream models | **full cascade** | base `:X.Y.Z` `:X.Y` `:latest` |
| tag `<image>-vX.Y.Z` | that model | **full** | `:X.Y.Z` `:X.Y` (fail-closed) |
| `workflow_dispatch` | chosen / all | **full** | no |
| feature branch push | — (workflow doesn't trigger) | — | — |

The rule: **a green PR means the full model-output gate ran** on the affected images, so a
release-impacting change cannot merge on smoke alone. `select` scopes builds to changed
paths (a docs-only PR builds no images — but the contract job still runs, so repo-state
checks always fire), so PR cost equals the blast radius of the
change. Promotion only ever happens on push-to-`main` / release tags, only on the *tested*
digest, and only if every test passed. During active development, iterate on a feature
branch and use `workflow_dispatch` for ad-hoc full runs.
