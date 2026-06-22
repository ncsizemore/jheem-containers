# jheem-containers

Monorepo for the JHEEM model containers — the shared base image plus the per-model containers that run
published JHEEM analyses and power the custom simulations on [jheem.org](https://jheem.org).

## Structure

- **`base/`** — the shared base image (`jheem-base`): the R environment (`rocker/r-ver`, digest-pinned),
  the `run` / `version` / simset-fetch tooling, and the model-agnostic custom-simulation orchestrator.
- **`models/`** — one directory per model, each building its image *from* the base:

  | Directory | Image |
  |-----------|-------|
  | `models/ryan-white-msa/` | `jheem-ryan-white-msa` |
  | `models/ryan-white-ajph/` | `jheem-ryan-white-ajph` |
  | `models/ryan-white-croi/` | `jheem-ryan-white-croi` |
  | `models/cdc-testing/` | `jheem-cdc-testing` |

  Each `models/<m>/tests/golden/` holds a production custom-sim artifact the image reproduces
  **bit-for-bit** (the regression reference).

## Status

Consolidated from five separate repos with **history preserved** (`git log`/`blame` trace through the
move). **Phase A** (relocation) — done. The CI matrix and **Phase B** (config-driven build) are in
progress. See the migration plan: `jheem-portal/docs/CONTAINER-MONOREPO-MIGRATION-PLAN.md`.

## Images & versioning

Images publish to `ghcr.io/<owner>/jheem-…`. Per-image **prefixed semver** tags (`<image>-vX.Y.Z` →
`jheem-…:X.Y.Z`); `main` pushes also produce `:latest` + `:sha`. Production pins specific semver tags via
`models.json` in jheem-backend.
