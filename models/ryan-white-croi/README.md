# CROI 2026 Ryan White State-Level Container

Container for the expanded 30-state CROI 2026 Ryan White analysis.

## Analysis Details

| Property | Value |
|----------|-------|
| States | 30 |
| Timeframe | 2026-2031 |
| Services Stop | July 2026 |
| Anchor Year | 2026 |

### Scenarios

- **Cessation** (`rw.end.26`): Services never resume
- **2.5-year Interruption** (`rw.p.intr.26`): Services resume Jan 2029
- **Conservative variants**: Lower losses of suppression

## Container Modes

### Batch Mode (Data Extraction)
Extract JSON data from trimmed simsets for web display.

```bash
docker run --rm \
  -v /path/to/simsets:/app/simulations \
  -v /path/to/output:/output \
  ghcr.io/ncsizemore/jheem-ryan-white-croi:latest \
  batch --city AL --scenarios cessation --outcomes incidence
```

### Trim Mode (Simset Preparation)
Trim raw simsets (1000 sims) to web-friendly size (80 sims).

```bash
docker run --rm \
  -v /path/to/raw:/data/raw \
  -v /path/to/trimmed:/data/trimmed \
  ghcr.io/ncsizemore/jheem-ryan-white-croi:latest \
  trim --state AL
```

Benchmark mode (single file timing):
```bash
docker run --rm \
  -v /path/to/raw:/data/raw \
  ghcr.io/ncsizemore/jheem-ryan-white-croi:latest \
  trim --state AL --benchmark
```

## Building

```bash
# Build with latest jheem_analyses
docker build -t jheem-ryan-white-croi .

# Build with specific commit
docker build --build-arg JHEEM_ANALYSES_COMMIT=abc123 -t jheem-ryan-white-croi .
```

## Related Repositories

- **jheem-portal**: Frontend application
- **jheem-backend**: Workflows and API
- **jheem-simulations**: Raw simulation data (GitHub Releases)
- **jheem-container-minimal**: AJPH 11-state container (frozen)

## Differences from AJPH Container

| Aspect | AJPH | CROI |
|--------|------|------|
| States | 11 | 30 |
| Timeframe | 2025-2030 | 2026-2031 |
| jheem_analyses | Pinned to `fc3fe1d2` | Latest HEAD |
| Scenarios | cessation, brief (1.5yr), prolonged (3.5yr) | cessation, 2.5yr interruption |
| Container | `jheem-container-minimal` | This repo |
