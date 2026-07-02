# Container promotion-gate test suite

The test layer of the build → **test-by-digest** → promote gate (per the independent
review). It tests an *exact candidate image*, never a rebuild between testing and
promotion.

## Layers

- **`test_smoke.py`** (fast, no simulation) — image `version`/provenance fields, and
  `test-workspace` loading the model's specification object. Cheap enough to gate every build.
- **`test_golden.py`** (`slow`, runs the simulation) —
  - **regression:** a fixed scenario reproduces the committed production golden `0.0`;
  - **perturbation:** a *non-default* parameter moves the intervention while baseline is
    unchanged — proving each parameter reaches the model. This is what catches the CDC
    env-var-name class of bug (a default-valued golden silently passed it).

`golden_compare.py` is the comparator: multi-slice, **null-vs-value is a mismatch**,
**duplicate keys fail**, per-role (baseline/intervention) breakdown.

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

## When the gate runs (merge / release policy)

| Event | Builds | Tests | Promotes |
|-------|--------|-------|----------|
| `pull_request` → main | affected images (`select`) | **full** (smoke + slow) | no |
| push → `main` | affected images | **full** | `:latest` (fail-closed) |
| tag `<image>-vX.Y.Z` | that image | **full** | `:X.Y.Z` `:X.Y` (fail-closed) |
| `workflow_dispatch` | chosen / all | **full** | no |
| feature branch push | — (workflow doesn't trigger) | — | — |

The rule: **a green PR means the full model-output gate ran** on the affected images, so a
release-impacting change cannot merge on smoke alone. `select` scopes builds to changed
paths (a docs-only PR builds and tests nothing), so PR cost equals the blast radius of the
change. Promotion only ever happens on push-to-`main` / release tags, only on the *tested*
digest, and only if every test passed. During active development, iterate on a feature
branch and use `workflow_dispatch` for ad-hoc full runs.
