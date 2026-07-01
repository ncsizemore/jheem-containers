# JHEEM Ryan White MSA Container

Model image for the frozen Ryan White MSA analysis. It extends
`ghcr.io/ncsizemore/jheem-base:1.6.5`, copies the validated workspace from the legacy model image, and
pins the runtime `jheem2` ref needed to reproduce the published simulation outputs.

Published image:

```bash
ghcr.io/ncsizemore/jheem-ryan-white-msa
```

Use `:latest` for local smoke checks and promoted semver tags for production pins.

## Analysis scope

| Property | Value |
| --- | --- |
| Geography | 31 cities/MSAs |
| Simulation release | `ryan-white-msa-v1.0.0` |
| Workspace source | `ghcr.io/ncsizemore/jheem-ryan-white-model:2.1.0` |
| Runtime `jheem2` ref | `54f669a139281f25cd87dfd0c25a01aca797777c` |

## Runtime

Invoked via `run` (standalone) or `custom` (the backend pipeline); a bare `docker run` prints `version`.

Useful local checks:

```bash
docker run --rm ghcr.io/ncsizemore/jheem-ryan-white-msa:latest test-workspace
```

```bash
docker run --rm --platform linux/amd64 \
  -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-ryan-white-msa:latest run \
  --location C.12580 \
  --param adap_loss=50 \
  --param oahs_loss=30 \
  --param other_loss=40 \
  --out /out/ryan-white-msa.json
```

## Compatibility note

MSA is intentionally different from the newer state-level images. The workspace is copied from the
legacy `jheem-ryan-white-model:2.1.0` image because rebuilding it from newer source/runtime combinations
serialized incompatible functions. The final image pins `jheem2` to the historical ref used for the MSA
simulation sets.

This is technical debt, but it is explicit technical debt: the model-image gate still validates the final
artifact by digest against golden output before promotion.

## Build metadata

| Argument | Current default | Purpose |
| --- | --- | --- |
| `BASE_VERSION` | `1.6.5` | Shared base image version tested for this frozen model. |

The final image exports provenance-oriented environment variables including `MODEL_ID`,
`SIMULATION_SCRIPT`, `SIMSET_RELEASE`, `JHEEM2_REF`, `JHEEM2_WORKSPACE_VERSION`, and `JHEEM_BASE_VERSION`.

## Test coverage

This model participates in the monorepo promotion gate:

- `test-workspace` smoke validation.
- Golden-output regression against checked-in reference artifacts.
- Targeted perturbation tests for custom-simulation behavior.

See [`../../tests/README.md`](../../tests/README.md) for the test contract and promotion policy.
