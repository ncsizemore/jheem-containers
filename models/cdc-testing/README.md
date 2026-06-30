# JHEEM CDC Testing Container

Model image for the JHEEM CDC Testing analysis. It extends `ghcr.io/ncsizemore/jheem-base:1.6.3`, builds
the CDC Testing workspace from `jheem_analyses`, and exposes the simulation runtime used by the JHEEM
backend.

Published image:

```bash
ghcr.io/ncsizemore/jheem-cdc-testing
```

Use `:latest` for local smoke checks and promoted semver tags for production pins.

## Runtime

Primary mode: `lambda`

Useful local checks:

```bash
docker run --rm ghcr.io/ncsizemore/jheem-cdc-testing:latest test-workspace
```

```bash
docker run --rm --platform linux/amd64 \
  -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-cdc-testing:latest run \
  --location CA \
  --param testing_reduction=100 \
  --param proportion_tested_regardless=50 \
  --out /out/cdc-testing.json
```

## What is model-specific here

| File | Purpose |
| --- | --- |
| `create_cdc_testing_workspace.R` | Creates the CDC Testing workspace from `jheem_analyses`. |
| `simple_cdc_testing.R` | Custom-simulation adapter copied into the base image's `simulation/` directory. |
| `cached/google_mobility_data.Rdata` | Runtime data copied into the build because it is not yet fully release-pinned upstream. |

Everything else - R packages, entrypoints, batch extraction, custom-simulation orchestration, and
simset-fetch tooling - comes from `jheem-base`.

## Build metadata

| Argument | Current default | Purpose |
| --- | --- | --- |
| `BASE_VERSION` | `1.6.3` | Shared base image version tested for this model. |
| `JHEEM_ANALYSES_COMMIT` | `51ac4957` | Source commit used to build the workspace. |

The final image exports provenance-oriented environment variables including `MODEL_ID`,
`SIMULATION_SCRIPT`, `SIMSET_RELEASE`, `JHEEM_ANALYSES_REF`, and `JHEEM_BASE_VERSION`.

## Test coverage

This model participates in the monorepo promotion gate:

- `test-workspace` smoke validation.
- Golden-output regression against checked-in reference artifacts.
- Targeted perturbation tests for custom-simulation behavior.

See [`../../tests/README.md`](../../tests/README.md) for the test contract and promotion policy.
