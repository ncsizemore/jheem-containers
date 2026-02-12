# JHEEM CDC Testing Container

Docker container for the JHEEM CDC Testing model. Extends the shared [jheem-base](https://github.com/ncsizemore/jheem-base) image.

## Usage

The container is published to GitHub Container Registry:

```bash
docker pull ghcr.io/ncsizemore/jheem-cdc-testing-model:latest
```

### Lambda Mode (Default)

```bash
docker run --rm -p 8080:8080 ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0 lambda
```

### Batch Mode (Data Generation)

```bash
docker run --rm ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0 batch \
  --state AL \
  --scenarios cessation \
  --outcomes incidence \
  --output-mode data
```

### Test Workspace

```bash
docker run --rm ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0 test-workspace
```

## Architecture

This container uses a thin wrapper pattern:

```
ghcr.io/ncsizemore/jheem-base:1.0.0    (shared R environment, ~150 lines)
  └── ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0  (this container, ~55 lines)
```

### What's in this container

| File | Purpose |
|------|---------|
| `create_cdc_testing_workspace.R` | Creates CDCT.SPECIFICATION and loads interventions |
| `cached/google_mobility_data.Rdata` | Mobility data (not in official cache yet) |

Everything else (R packages, batch_plot_generator.R, entrypoint) comes from jheem-base.

## Building

```bash
docker build -t jheem-cdc-testing-model .
```

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `BASE_VERSION` | `1.0.0` | jheem-base image version |
| `JHEEM_ANALYSES_COMMIT` | `fc3fe1d...` | jheem_analyses git commit |

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [jheem-base](https://github.com/ncsizemore/jheem-base) | Shared base image |
| [jheem-backend](https://github.com/ncsizemore/jheem-backend) | Workflows that run this container |
| [jheem-portal](https://github.com/ncsizemore/jheem-portal) | Frontend that displays generated data |
