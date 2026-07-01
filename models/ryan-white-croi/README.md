# JHEEM Ryan White CROI Container

Model image for the Ryan White CROI 2026 state-level analysis. It extends
`ghcr.io/ncsizemore/jheem-base:1.6.3`, builds the CROI Ryan White workspace from `jheem_analyses`, and
exposes the simulation runtime used by the JHEEM backend.

Published image:

```bash
ghcr.io/ncsizemore/jheem-ryan-white-croi
```

Use `:latest` for local smoke checks and promoted semver tags for production pins.

## Analysis scope

| Property | Value |
| --- | --- |
| Geography | 30 states |
| Timeframe | 2026-2031 |
| Anchor year | 2026 |
| Simulation release | `ryan-white-state-v2.0.0` |

## Runtime

Invoked via `run` (standalone) or `custom` (the backend pipeline); a bare `docker run` prints `version`.

Useful local checks:

```bash
docker run --rm ghcr.io/ncsizemore/jheem-ryan-white-croi:latest test-workspace
```

```bash
docker run --rm --platform linux/amd64 \
  -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-ryan-white-croi:latest run \
  --location CO \
  --param adap_loss=50 \
  --param oahs_loss=30 \
  --param other_loss=40 \
  --out /out/ryan-white-croi.json
```

## What is model-specific here

| File | Purpose |
| --- | --- |
| `create_ryan_white_workspace.R` | Creates the Ryan White CROI workspace. |
| `trim_simsets.R` | CROI-specific trimming support for large simulation files. |
| `cached/google_mobility_data.Rdata` | Runtime data copied into the build because it is not yet fully release-pinned upstream. |

Everything else - R packages, entrypoints, batch extraction, custom-simulation orchestration, and
simset-fetch tooling - comes from `jheem-base`.

## Build metadata

| Argument | Current default | Purpose |
| --- | --- | --- |
| `BASE_VERSION` | `1.6.3` | Shared base image version tested for this model. |
| `JHEEM_ANALYSES_COMMIT` | `250ffc8aafcabe00c1bca20df831bf9637c2dd12` | Source commit traced to the deployed image build and golden output. |

The final image exports provenance-oriented environment variables including `MODEL_ID`,
`SIMULATION_SCRIPT`, `SIMSET_RELEASE`, `JHEEM_ANALYSES_REF`, and `JHEEM_BASE_VERSION`.

## Test coverage

This model participates in the monorepo promotion gate:

- `test-workspace` smoke validation.
- Golden-output regression against checked-in reference artifacts.
- Targeted perturbation tests for custom-simulation behavior.

See [`../../tests/README.md`](../../tests/README.md) for the test contract and promotion policy.
