# JHEEM Base Image

Shared R environment for all JHEEM model containers. Model containers extend this base image and add only their workspace creation logic.

## Usage

Model containers should use this as their base:

```dockerfile
ARG BASE_VERSION=1.2.0
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION}

# Add model-specific workspace
COPY --from=workspace-builder /app/my_workspace.RData ./

ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["batch"]
```

## What's Included

| Component | Description |
|-----------|-------------|
| R 4.4.2 | Base R installation |
| renv.lock | Pinned R packages including jheem2, plotly, jsonlite |
| batch_plot_generator.R | Auto-detects workspace, generates plot/data output |
| custom_simulation.R | Custom simulation mode (load workspace, run intervention, save simsets) |
| container_entrypoint.sh | Routes to batch, custom, trim, or debug modes |
| trim_simsets.R | Trims raw simsets to web-friendly size |
| plotting/ | Plot rendering dependencies |
| simulation/ | Simulation utilities (intervention scripts) |

## Modes

The entrypoint supports several modes:

| Mode | Description |
|------|-------------|
| `batch` | Extract data from pre-run simulations. Supports `--output-mode data` (JSON) or `plot` (Plotly). |
| `custom` | Run custom simulation with user parameters. Saves simsets in batch-compatible layout for subsequent `batch` extraction. |
| `trim` | Trim raw simsets to web-ready size |
| `test-workspace` | Test workspace loading (auto-detects) |
| `debug` | Interactive bash shell |

## Version-Matching Requirement

**The jheem2 version in the base image must match the version used to generate the simsets that the container will process.** The diffeq engine dynamics changed at commit `76859f2d` (April 2025) — simsets generated before this commit require pre-fix jheem2, and vice versa.

Current versions:

| Tag | jheem2 | Use with |
|-----|--------|----------|
| v1.2.0 | 1.6.2 (pre-fix, pinned to `54f669a`) | MSA simsets (`ryan-white-msa-v1.0.0`) |
| v1.1.1 | latest (post-fix) | CROI simsets (`ryan-white-state-v2.0.0`) |
| v1.0.0 | latest (post-fix) | CDC Testing simsets |

See the [custom simulations plan](https://github.com/ncsizemore/jheem-portal/blob/main/docs/CUSTOM-SIMULATIONS-PLAN.md) for full version matrix and context.

## Building

```bash
docker build -t jheem-base .
```

## Tagging

Use semantic versioning. The Dockerfile's `ARG BASE_VERSION` default in downstream containers is the source of truth for which base version they use — workflows should not override it unless explicitly specified.

When base image updates, model containers should:
1. Update their Dockerfile `ARG BASE_VERSION` default
2. Test builds
3. Tag new model version

**Cascade rebuild is currently disabled** — different models need different jheem2 versions. Rebuild each model container individually.

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [jheem-ryan-white-container](https://github.com/ncsizemore/jheem-container-minimal) | MSA + AJPH model |
| [jheem-ryan-white-croi-container](https://github.com/ncsizemore/jheem-ryan-white-croi-container) | CROI model |
| [jheem-cdc-testing-container](https://github.com/ncsizemore/jheem-cdc-testing-container) | CDC Testing model |
| [jheem-backend](https://github.com/ncsizemore/jheem-backend) | Workflows that run these containers |
