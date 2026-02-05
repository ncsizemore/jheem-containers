# JHEEM CDC Testing Container

Docker container for the JHEEM CDC Testing model, used to generate plot data for the JHEEM Portal CDC Testing explorer.

## Overview

This container packages the JHEEM CDC Testing epidemiological model with its R dependencies, enabling batch generation of plot data from pre-run simulations.

**Model Version:** `cdct` (CDC Testing)
**Anchor Year:** 2025 (intervention scenarios start 2025)
**Parent Model:** EHE (Ending the HIV Epidemic)

## Quick Start

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/ncsizemore/jheem-cdc-testing-model:latest

# Run batch plot generation
docker run --rm \
  -v /path/to/simulations:/app/simulations:ro \
  -v /path/to/output:/output \
  ghcr.io/ncsizemore/jheem-cdc-testing-model:latest \
  batch \
  --city AL \
  --scenarios cessation,brief_interruption,prolonged_interruption \
  --outcomes incidence,diagnosed.prevalence,cdc.funded.tests \
  --output-dir /output
```

## Scenarios

| Scenario ID | File Pattern | Description |
|-------------|--------------|-------------|
| `cessation` | `cdct.end` | Complete cessation of CDC-funded testing |
| `brief_interruption` | `cdct.bintr` | Brief interruption of CDC testing |
| `prolonged_interruption` | `cdct.pintr` | Prolonged interruption of CDC testing |

## Outcomes

Standard outcomes:
- `incidence` - Rate of new HIV infections
- `new` - New diagnoses
- `diagnosed.prevalence` - Prevalence (diagnosed)
- `testing` - HIV testing rates
- `prep.uptake` - PrEP coverage
- `suppression` - Viral suppression
- `awareness` - Knowledge of status

CDC-specific outcomes:
- `cdc.funded.tests` - Number of CDC-funded HIV tests
- `cdc.funded.diagnoses` - Diagnoses from CDC-funded testing

## Simulation File Format

Expected file naming convention:
```
cdct_final.ehe.state-1000_{STATE}_{scenario}.Rdata
```

Example:
```
simulations/
└── AL/
    ├── cdct_final.ehe.state-1000_AL_noint.Rdata      (baseline)
    ├── cdct_final.ehe.state-1000_AL_cdct.end.Rdata   (cessation)
    ├── cdct_final.ehe.state-1000_AL_cdct.bintr.Rdata (brief)
    └── cdct_final.ehe.state-1000_AL_cdct.pintr.Rdata (prolonged)
```

## Building Locally

```bash
# Clone the repository
git clone https://github.com/ncsizemore/jheem-cdc-testing-container.git
cd jheem-cdc-testing-container

# Build the container
docker build -t jheem-cdc-testing-model .

# Build with specific jheem_analyses commit
docker build --build-arg JHEEM_ANALYSES_COMMIT=abc123 -t jheem-cdc-testing-model .
```

## Related Repositories

- [jheem-portal](https://github.com/ncsizemore/jheem-portal) - Frontend application
- [jheem-backend](https://github.com/ncsizemore/jheem-backend) - Workflows and configuration
- [jheem-simulations](https://github.com/ncsizemore/jheem-simulations) - Simulation data releases
- [jheem-container-minimal](https://github.com/ncsizemore/jheem-container-minimal) - Ryan White container (base)
