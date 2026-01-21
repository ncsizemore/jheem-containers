# CROI Container Development Guide

This document captures lessons learned during the development of the CROI 2026 container, particularly around the complexities of containerizing jheem2 simulation workflows. These findings will be instructive for future model containers.

## Architecture Overview

The container uses a multi-stage Docker build:

```
┌─────────────────────────────────────────────────────────────────┐
│  Stage 1: jheem-base                                            │
│  - R 4.4.2 with renv                                            │
│  - All R packages installed                                     │
│  - System libraries and symlinks                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 2: workspace-builder                                     │
│  - Clones jheem_analyses                                        │
│  - Downloads cached data files                                  │
│  - Runs create_ryan_white_workspace.R                           │
│  - Produces ryan_white_workspace.RData (~1.5GB)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 3: ryan-white-model (runtime)                            │
│  - Copies workspace from builder                                │
│  - Copies runtime scripts (trim, batch, etc.)                   │
│  - Copies required data directories                             │
│  - Minimal footprint for deployment                             │
└─────────────────────────────────────────────────────────────────┘
```

## The Workspace: Why It's Complex

The `ryan_white_workspace.RData` file is the heart of the container. It captures:

1. **jheem2 internal functions** - Exported from package namespace to GlobalEnv
2. **Model specification** - `RW.SPECIFICATION` with all model parameters
3. **Data managers** - `RW.DATA.MANAGER`, `WEB.DATA.MANAGER`
4. **Registered state** - Version manager, ontology mappings, interventions
5. **R6 class generators** - For simulation object operations

This workspace allows the container to run simulations without sourcing the full jheem_analyses codebase at runtime.

## jheem2 Hidden State: Lessons Learned

jheem2 uses several internal environments that maintain state. When containerizing, this state must be captured during build and restored at runtime. Here's what we discovered:

### 1. VERSION.MANAGER
**What it does:** Tracks registered model versions (e.g., 'rw' for Ryan White)
**Location:** `asNamespace("jheem2")$VERSION.MANAGER`
**Captured as:** `.jheem2_state$version_manager`

### 2. ONTOLOGY.MAPPING.MANAGER
**What it does:** Maps between different data ontologies
**Location:** `get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))`
**Captured as:** `.jheem2_state$ontology_mapping_manager`

### 3. INTERVENTION.MANAGER
**What it does:** Registry of all intervention definitions (rw.end.26, etc.)
**Location:** `get("INTERVENTION.MANAGER", envir = asNamespace("jheem2"))`
**Captured as:** `.jheem2_state$intervention_manager`

**Critical:** Interventions are registered when `create.intervention()` is called with a `code` parameter. The workspace must source `ryan_white_interventions.R` to register all intervention codes.

### 4. JHEEM.SOLVER.TRACKING
**What it does:** Tracks solver state during simulation runs
**Location:** `get("JHEEM.SOLVER.TRACKING", envir = asNamespace("jheem2"))`
**How we handle it:** Export directly to GlobalEnv (it's an environment, not captured in .jheem2_state)

### 5. R6 Class Generators
**What they are:** JHEEM.RUN.METADATA, SIMULATION.METADATA, SOLVER.METADATA, etc.
**Why needed:** Simulation objects reference these classes; they must exist for operations like `thin()` and `rerun.simulations()`
**Captured as:** `.jheem2_state$r6_class_generators`

## Required Packages Not Obviously Needed

Some packages are used internally by jheem2 but not explicitly loaded:

| Package | Used For | Symptom If Missing |
|---------|----------|-------------------|
| `distributions` | `generate.random.samples()` | "could not find function" error during rerun |
| `locations` | `get.contained.locations()` | "could not find function" error during engine creation |
| `ks` | Kernel density estimation for intervention effects | Error during intervention registration |

## Required Data Directories

The runtime container needs these directories from jheem_analyses:

```dockerfile
# Object version cache - for cached computations
COPY --from=workspace-builder /app/jheem_analyses/commoncode/object_for_version_cache /jheem_analyses/commoncode/object_for_version_cache

# Data files - IDU initiation rates, etc.
COPY --from=workspace-builder /app/jheem_analyses/data_files /jheem_analyses/data_files

# Cached data - COVID mobility, pre-computed values
COPY --from=workspace-builder /app/jheem_analyses/cached /jheem_analyses/cached
```

These paths are hard-coded in jheem_analyses with relative paths like `../jheem_analyses/...`, so the directory structure must match.

## Memory Requirements

**Minimum for trimming operations: 16GB**

Memory breakdown during trim operation:
| Stage | Memory (MB) | Notes |
|-------|-------------|-------|
| Workspace loaded | ~4,700 | Base memory before any simset |
| After loading 850MB simset | ~5,800 | Simset expands in memory |
| After thinning | ~6,100 | Thinned copy created |
| During rerun engine creation | ~11,000+ | Peak usage |

The ~4.7GB workspace baseline means **GitHub Actions free runners (7GB) are not viable** for trimming operations.

**Options for running trimming:**
1. Local machine with Docker set to 16GB RAM
2. Campus server with sufficient RAM
3. GitHub Actions with 16GB runner (~$0.008/min, ~$3 for full 30-state run)

## Issues Encountered and Solutions

### Issue 1: OOM During Engine Creation
**Symptom:** Process dies silently with exit code 137
**Cause:** Docker memory limit too low (default ~8GB)
**Solution:** Increase Docker Desktop memory to 16GB

### Issue 2: "could not find function generate.random.samples"
**Symptom:** Error during `rerun.simulations()` for baseline/noint files
**Cause:** `distributions` package not loaded explicitly
**Solution:** Add `library(distributions)` to trim_simsets.R

### Issue 3: "intervention.code 'rw.end.26' not registered"
**Symptom:** Error during `rerun.simulations()` for intervention files
**Cause:** Interventions weren't registered in workspace
**Solution:**
1. Source `ryan_white_interventions.R` during workspace creation
2. Capture `INTERVENTION.MANAGER` state
3. Restore intervention registry at runtime

### Issue 4: "object 'JHEEM.SOLVER.TRACKING' not found"
**Symptom:** Error during simulation re-run
**Cause:** Internal environment not exported
**Solution:** Export `JHEEM.SOLVER.TRACKING` to GlobalEnv during workspace creation

### Issue 5: COVID Mobility Data Lookup Failure
**Symptom:** "Cannot get COVID mobility data for 'AL' - no data are available"
**Cause:** FIPS codes in `google_mobility_data.Rdata` were malformed (missing leading zeros)
**Solution:** Replace with corrected data file

### Issue 6: Missing IDU Initiation Data
**Symptom:** "invalid 'description' argument" in file() call
**Cause:** `data_files/idu_initiation/` directory not copied to runtime container
**Solution:** Add COPY command for data_files directory

## Checklist for Future Model Containers

When creating a new model container:

- [ ] Identify all packages used (check for internal imports)
- [ ] Identify all internal jheem2 environments that need state preservation
- [ ] Source all necessary registration files (interventions, etc.)
- [ ] Copy all data directories referenced with relative paths
- [ ] Test with realistic memory constraints
- [ ] Verify full pipeline: load simset → process → save → load again → use

## Trimming Pipeline

The trimming operation:
1. Loads raw simset (1000 simulations, ~850MB file)
2. Thins to 80 simulations
3. Calls `rerun.simulations()` with truncated time range
4. Saves web-ready simset (~55-60MB file)

**Performance benchmarks (Alabama, 5 intervention files):**
- Total time: ~15 minutes per state
- Estimated 30 states: ~6 hours
- Output: ~280MB per state, ~8.4GB total

## Verification Checklist

After trimming, verify:

- [ ] Trimmed simsets load correctly
- [ ] Data extraction produces valid JSON
- [ ] JSON structure matches web app expectations
- [ ] Plots render correctly in frontend
- [ ] All intervention scenarios work
- [ ] Time range in output matches expected (2016-2036)

## Related Files

- `create_ryan_white_workspace.R` - Workspace creation with state capture
- `trim_simsets.R` - Trimming script with state restoration
- `restore_jheem2_state.R` - Shared restoration logic (if extracted)
- `Dockerfile` - Multi-stage build definition
