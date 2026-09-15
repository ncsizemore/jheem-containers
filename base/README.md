# JHEEM Base Image

Shared R runtime for the JHEEM model images in this monorepo. It is published as
`ghcr.io/ncsizemore/jheem-base`; downstream model images extend it and add only model-specific workspace
construction or a prebuilt workspace.

The base image exists to make the JHEEM runtime boring: one pinned R/system-dependency layer, one set of
common entrypoints, and one place for custom-simulation and output-generation tooling.

## What is included

| Component | Purpose |
| --- | --- |
| `rocker/r-ver:4.4.2` | Ubuntu 24.04/R 4.4.2 base image, pinned by digest in the Dockerfile. |
| `renv.lock` | Pinned R package set, including `jheem2`, `plotly`, and `jsonlite`. |
| `container_entrypoint.sh` | Routes model images into batch, custom, trim, test, debug, or lambda modes. |
| `batch_plot_generator.R` | Extracts JSON data or Plotly output from pre-run simulation sets. |
| `custom_simulation.R` | Runs user-parameterized simulations and writes batch-compatible outputs. |
| `fetch_simset.R` | Downloads simulation-set releases with retry/resume/verification behavior. |
| `plotting/`, `simulation/`, `tests/` | Shared plotting, intervention, and runtime-test utilities. |

## Entrypoint modes

| Mode | Purpose |
| --- | --- |
| `batch` | Extract data or plot output from pre-run simulations. |
| `custom` | Run a custom simulation with user parameters and save follow-on batch outputs. |
| `trim` | Trim raw simulation sets into web-ready artifacts. |
| `test-workspace` | Load and validate the model workspace. |
| `debug` | Start an interactive shell. |
| `lambda` | Run the HTTP/Lambda-style adapter used by serverless or request-driven paths. |

## Version compatibility

The base image is not a universally safe `latest` layer. Some JHEEM simulation sets are sensitive to
`jheem2` runtime behavior, so each model Dockerfile pins the base version it has been tested against.

Current downstream defaults:

| Model image | Base version | Notes |
| --- | --- | --- |
| `jheem-ryan-white-msa` | `1.7.0` | Published MSA analysis; prebuilt workspace, `jheem2` pinned to the compatible historical ref. |
| `jheem-ryan-white-ajph` | `1.7.0` | Heavy state model; large simsets rely on the base's fetch + release-API retry/resume/verify. |
| `jheem-ryan-white-croi` | `1.7.0` | Heavy state model; large simsets rely on the base's fetch + release-API retry/resume/verify. |
| `jheem-cdc-testing` | `1.7.0` | Heavy state model; large simsets rely on the base's fetch + release-API retry/resume/verify. |

Downstream models pin this base **by digest** (`…:${BASE_VERSION}@sha256:…`), not the mutable tag: a
`cache-from: type=gha` build once served stale base layers for a tag, silently shipping models without the
base's fixes. `tests/test_base_pin.py` enforces the pin against the registry on every PR. The model-image
gate validates each model candidate by digest. A base-candidate cascade now builds every model from the exact
candidate base digest and runs every downstream behavior test before a base tag can be promoted.

## Usage from a model Dockerfile

```dockerfile
ARG BASE_VERSION=1.7.0
# Pin by digest, not the mutable tag (a gha-cache build can otherwise serve stale
# base layers). Update both the version and the digest on a base bump.
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION}@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3

# Add model-specific workspace/scripts here.
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["version"]
```

## Local build

From this directory:

```bash
docker build -t ghcr.io/ncsizemore/jheem-base:local .
```

## Release notes

- **`base:1.6.4` is yanked.** 1.6.4 shipped a broken `fetch_simset.R` (a curl code-capture that misbehaves
  under R's `system2`); the promotion gate caught it before any model pinned it. It was superseded by 1.6.5,
  and the current tested base is 1.7.0. The old tags remain published under the no-retag policy, but nothing
  should build `FROM` 1.6.4.
- Downstream model Dockerfiles own their `ARG BASE_VERSION` defaults.
- Do not force all models to the same base tag unless the affected model goldens have passed.
- Base promotion requires the full candidate-base-to-model compatibility cascade and an explicit
  `base-vX.Y.Z` tag.

See the top-level [`README.md`](../README.md) for the monorepo release model.
