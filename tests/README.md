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

`test_config.json` is the interim per-model manifest (image, golden scenario,
perturbation). Phase B's canonical `models.yml` should generate or validate it rather
than it being a separate copy.
