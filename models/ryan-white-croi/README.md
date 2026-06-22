# JHEEM Ryan White CROI Container

Docker container for the CROI 2026 Ryan White 30-state analysis. Extends the shared [jheem-base](https://github.com/ncsizemore/jheem-base) image.

## Analysis Details

| Property | Value |
|----------|-------|
| States | 30 |
| Timeframe | 2026-2031 |
| Anchor Year | 2026 |

### Scenarios

- **Cessation** (`rw.end.26`): Services never resume
- **2.5-year Interruption** (`rw.p.intr.26`): Services resume Jan 2029
- **Conservative variants**: Lower losses of suppression

## Usage

```bash
docker pull ghcr.io/ncsizemore/jheem-ryan-white-croi:1.0.0
```

### Batch Mode (Data Extraction)

```bash
docker run --rm ghcr.io/ncsizemore/jheem-ryan-white-croi:1.0.0 batch \
  --state AL \
  --scenarios cessation \
  --outcomes incidence \
  --output-mode data
```

### Test Workspace

```bash
docker run --rm ghcr.io/ncsizemore/jheem-ryan-white-croi:1.0.0 test-workspace
```

## Architecture

```
ghcr.io/ncsizemore/jheem-base:1.0.0           (shared R environment, jheem2 latest/post-fix)
  └── ghcr.io/ncsizemore/jheem-ryan-white-croi:1.0.0  (this container)
```

### What's in this container

| File | Purpose |
|------|---------|
| `create_ryan_white_workspace.R` | Creates RW.SPECIFICATION with CROI anchor year (2026) |
| `cached/google_mobility_data.Rdata` | Mobility data (not in official cache yet) |

Everything else (R packages, batch_plot_generator.R, custom_simulation.R, entrypoint) comes from jheem-base.

Note: CROI also installs jheem2 from dev branch (required for compatibility with latest jheem_analyses).

### Version Matching

This container uses jheem-base v1.0.0 with post-fix jheem2. The CROI simsets (`ryan-white-state-v2.0.0`) were generated after the diffeq fix (`76859f2d`), so the versions match. See jheem-base README for details on version-matching requirements.

## Building

```bash
docker build -t jheem-ryan-white-croi .
```

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `BASE_VERSION` | `1.0.0` | jheem-base image version (source of truth — workflow defers to this) |
| `JHEEM_ANALYSES_COMMIT` | `HEAD` | jheem_analyses git commit |

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [jheem-base](https://github.com/ncsizemore/jheem-base) | Shared base image |
| [jheem-backend](https://github.com/ncsizemore/jheem-backend) | Workflows that run this container |
| [jheem-portal](https://github.com/ncsizemore/jheem-portal) | Frontend that displays generated data |
