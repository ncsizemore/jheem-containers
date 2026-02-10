# JHEEM Base Image

Shared R environment for all JHEEM model containers. Model containers extend this base image and add only their workspace creation logic.

## Usage

Model containers should use this as their base:

```dockerfile
ARG BASE_VERSION=1.0.0
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
| batch_plot_generator.R | Auto-detects workspace, generates plot data |
| container_entrypoint.sh | Routes to batch, lambda, trim, or debug modes |
| trim_simsets.R | Trims raw simsets to web-friendly size |
| plotting/ | Plot rendering dependencies |
| simulation/ | Simulation utilities |

## Modes

The entrypoint supports several modes:

| Mode | Description |
|------|-------------|
| `batch` | Generate plot data from pre-run simulations |
| `lambda` | Run custom simulations (for serverless) |
| `trim` | Trim raw simsets to web-ready size |
| `test-workspace` | Test workspace loading (auto-detects) |
| `debug` | Interactive bash shell |

## Building

```bash
docker build -t jheem-base .
```

## Tagging

Use semantic versioning:
- `v1.0.0` - First stable release
- `v1.1.0` - Added new feature
- `v1.0.1` - Bug fix

When base image updates, model containers should:
1. Update their `BASE_VERSION` build arg
2. Test builds
3. Tag new model version

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [jheem-ryan-white-container](https://github.com/ncsizemore/jheem-container-minimal) | MSA + AJPH model |
| [jheem-ryan-white-croi-container](https://github.com/ncsizemore/jheem-ryan-white-croi-container) | CROI model |
| [jheem-cdc-testing-container](https://github.com/ncsizemore/jheem-cdc-testing-container) | CDC Testing model |
| [jheem-backend](https://github.com/ncsizemore/jheem-backend) | Workflows that run these containers |
