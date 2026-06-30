# JHEEM Ryan White AJPH Container

Model image for the Ryan White AJPH state-level analysis. It extends
`ghcr.io/ncsizemore/jheem-base:1.6.2`, builds the Ryan White workspace from `jheem_analyses`, and exposes
the batch/runtime path used by JHEEM.

Published image:

```bash
ghcr.io/ncsizemore/jheem-ryan-white-ajph
```

Use `:latest` for local smoke checks and promoted semver tags for production pins.

## Analysis scope

| Property | Value |
| --- | --- |
| Geography | 11 states |
| Timeframe | 2025-2030 |
| Simulation release | `ryan-white-ajph-v1.0.0` |

## Runtime

Primary mode: `batch`

Useful local checks:

```bash
docker run --rm ghcr.io/ncsizemore/jheem-ryan-white-ajph:latest test-workspace
```

```bash
docker run --rm --platform linux/amd64 \
  -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-ryan-white-ajph:latest run \
  --location FL \
  --param adap_loss=50 \
  --param oahs_loss=30 \
  --param other_loss=40 \
  --out /out/ryan-white-ajph.json
```

## What is model-specific here

| File | Purpose |
| --- | --- |
| `create_ryan_white_workspace.R` | Creates the Ryan White AJPH workspace. |
| `cached/google_mobility_data.Rdata` | Runtime data copied into the build because it is not yet fully release-pinned upstream. |

Everything else - R packages, entrypoints, batch extraction, custom-simulation orchestration, and
simset-fetch tooling - comes from `jheem-base`.

## Build metadata

| Argument | Current default | Purpose |
| --- | --- | --- |
| `BASE_VERSION` | `1.6.2` | Shared base image version tested for this model. |
| `JHEEM_ANALYSES_COMMIT` | `fc3fe1d2d5f859b322414da8b11f0182e635993b` | Source commit used to build the workspace. |

The final image exports provenance-oriented environment variables including `MODEL_ID`,
`SIMULATION_SCRIPT`, `SIMSET_RELEASE`, `JHEEM_ANALYSES_REF`, and `JHEEM_BASE_VERSION`.

## Test coverage

This model participates in the monorepo promotion gate:

- `test-workspace` smoke validation.
- Golden-output regression against checked-in reference artifacts.
- Targeted perturbation tests for custom-simulation behavior.

See [`../../tests/README.md`](../../tests/README.md) for the test contract and promotion policy.
