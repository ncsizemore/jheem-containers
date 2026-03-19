# JHEEM CDC Testing Container

Docker container for the JHEEM CDC Testing model. Extends the shared [jheem-base](https://github.com/ncsizemore/jheem-base) image.

## Usage

The container is published to GitHub Container Registry:

```bash
docker pull ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0
```

### Batch Mode (Data Extraction)

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

```
ghcr.io/ncsizemore/jheem-base:1.0.0           (shared R environment, jheem2 latest/post-fix)
  └── ghcr.io/ncsizemore/jheem-cdc-testing-model:2.0.0  (this container)
```

### What's in this container

| File | Purpose |
|------|---------|
| `create_cdc_testing_workspace.R` | Creates CDCT.SPECIFICATION and loads interventions |
| `cached/google_mobility_data.Rdata` | Mobility data (not in official cache yet) |

Everything else (R packages, batch_plot_generator.R, custom_simulation.R, entrypoint) comes from jheem-base.

### Version Matching

This container uses jheem-base v1.0.0 with post-fix jheem2. The CDC Testing simsets (`cdc-testing-v1.0.0`) generation date relative to the diffeq fix (`76859f2d`) has not been verified — empirical testing required before enabling custom simulations. See jheem-base README for details.

## Building

```bash
docker build -t jheem-cdc-testing-model .
```

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `BASE_VERSION` | `1.0.0` | jheem-base image version (source of truth — workflow defers to this) |
| `JHEEM_ANALYSES_COMMIT` | `fc3fe1d...` | jheem_analyses git commit |

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [jheem-base](https://github.com/ncsizemore/jheem-base) | Shared base image |
| [jheem-backend](https://github.com/ncsizemore/jheem-backend) | Workflows that run this container |
| [jheem-portal](https://github.com/ncsizemore/jheem-portal) | Frontend that displays generated data |
