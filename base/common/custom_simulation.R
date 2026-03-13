#!/usr/bin/env Rscript

# =============================================================================
# custom_simulation.R
# =============================================================================
# Runs a custom simulation with user-specified parameters and saves the
# resulting simset to disk. Data extraction is handled separately by calling
# batch_plot_generator.R with --output-mode data (reusing the prerun pipeline).
#
# Pipeline:
#   1. Load workspace + restore jheem2 state
#   2. Load base simset
#   3. Create intervention with user parameters
#   4. Run forward simulation
#   5. Save simsets in batch-compatible directory layout
#
# The output directory will contain:
#   {OUTPUT_DIR}/simulations/ryan-white/base/{LOCATION}_base.Rdata
#   {OUTPUT_DIR}/simulations/ryan-white/prerun/{LOCATION}/{SCENARIO_KEY}.Rdata
#
# This layout matches what batch_plot_generator.R expects, so extraction
# can be done by running:
#   batch --city {LOCATION} --scenarios {SCENARIO_KEY} --output-mode data ...
#
# Environment variables:
#   LOCATION        - Location code (e.g., "AL", "C.12580")
#   SCENARIO_KEY    - Deterministic key from params (e.g., "a50-o30-r40")
#   SCENARIO_LABEL  - Human-readable label (passed through, used by extraction)
#   ADAP_LOSS       - ADAP suppression loss % (default: 50)
#   OAHS_LOSS       - OAHS suppression loss % (default: 30)
#   OTHER_LOSS      - Other suppression loss % (default: 40)
#   OUTPUT_DIR      - Output directory for saved simsets (default: /output)
# =============================================================================

total_start <- proc.time()

cat("===========================================\n")
cat("CUSTOM SIMULATION\n")
cat("===========================================\n\n")

# --- Parse configuration from environment ---
LOCATION <- Sys.getenv("LOCATION", "AL")
ADAP_LOSS <- as.numeric(Sys.getenv("ADAP_LOSS", "50"))
OAHS_LOSS <- as.numeric(Sys.getenv("OAHS_LOSS", "30"))
OTHER_LOSS <- as.numeric(Sys.getenv("OTHER_LOSS", "40"))
OUTPUT_DIR <- Sys.getenv("OUTPUT_DIR", "/output")

SCENARIO_KEY <- Sys.getenv("SCENARIO_KEY", sprintf("a%g-o%g-r%g", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))
SCENARIO_LABEL <- Sys.getenv("SCENARIO_LABEL", sprintf("ADAP %g%%, OAHS %g%%, Other %g%%", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))

cat(sprintf("  Location:       %s\n", LOCATION))
cat(sprintf("  Scenario key:   %s\n", SCENARIO_KEY))
cat(sprintf("  Scenario label: %s\n", SCENARIO_LABEL))
cat(sprintf("  Parameters:     ADAP=%g%%, OAHS=%g%%, Other=%g%%\n", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))
cat(sprintf("  Output:         %s\n", OUTPUT_DIR))
cat("\n")

# =============================================================================
# Phase 1: Load workspace and dependencies
# =============================================================================
cat("--- Phase 1: Load workspace ---\n")
t1 <- proc.time()

suppressPackageStartupMessages({
  library(jheem2)
  library(locations)
})

# Export jheem2 internals to global environment
pkg_env <- asNamespace("jheem2")
for (fn in ls(pkg_env, all.names = TRUE)) {
  if (exists(fn, pkg_env, inherits = FALSE) && is.function(get(fn, pkg_env))) {
    assign(fn, get(fn, pkg_env), envir = .GlobalEnv)
  }
}

# Auto-detect and load workspace
workspace_files <- list.files(pattern = "_workspace\\.RData$", ignore.case = TRUE)
if (length(workspace_files) == 0) stop("No workspace file found")
load(workspace_files[1])
cat(sprintf("  Loaded workspace: %s\n", workspace_files[1]))

# Restore jheem2 internal state
vm <- asNamespace("jheem2")$VERSION.MANAGER
for (name in names(.jheem2_state$version_manager)) {
  assign(name, .jheem2_state$version_manager[[name]], envir = vm)
}
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
for (name in names(.jheem2_state$ontology_mapping_manager)) {
  assign(name, .jheem2_state$ontology_mapping_manager[[name]], envir = ont_mgr)
}

library(distributions)

# Workaround for jheem2 bug: populate_outcomes_array crashes on NULL
# new_values/old_times (affects aids.diagnoses/aids.deaths in state simsets)
original_poa <- get("populate_outcomes_array", envir = asNamespace("jheem2"))
patched_poa <- function(desired_times, char_desired_times, n_per_time,
                         new_values, new_times, old_values, old_times, prior_sim_index) {
  if (is.null(new_values) || is.null(old_times)) return(old_values)
  original_poa(desired_times, char_desired_times, n_per_time,
               new_values, new_times, old_values, old_times, prior_sim_index)
}
environment(patched_poa) <- asNamespace("jheem2")
assignInNamespace("populate_outcomes_array", patched_poa, ns = "jheem2")

t1_elapsed <- (proc.time() - t1)["elapsed"]
cat(sprintf("  Time: %.1f sec\n\n", t1_elapsed))

# =============================================================================
# Phase 2: Load base simset
# =============================================================================
cat("--- Phase 2: Load base simset ---\n")
t2 <- proc.time()

simset_files <- list.files("/data/", pattern = "\\.Rdata$", full.names = TRUE, ignore.case = TRUE)
if (length(simset_files) == 0) stop("No .Rdata files found in /data/")

location_match <- grep(LOCATION, simset_files, fixed = TRUE)
if (length(location_match) == 0) {
  stop(sprintf("No simset file matching '%s' found in /data/. Available: %s",
               LOCATION, paste(basename(simset_files), collapse = ", ")))
}
simset_path <- simset_files[location_match[1]]
cat(sprintf("  Loading: %s (%.0f MB)\n", basename(simset_path), file.size(simset_path) / 1024 / 1024))

loaded <- load(simset_path)
base_simset <- get(loaded[1])

n_sims <- tryCatch(base_simset$n.sim, error = function(e) "unknown")
cat(sprintf("  Simulations: %s\n", n_sims))

t2_elapsed <- (proc.time() - t2)["elapsed"]
cat(sprintf("  Time: %.1f sec\n\n", t2_elapsed))

# =============================================================================
# Phase 3: Run custom simulation
# =============================================================================
cat("--- Phase 3: Run custom simulation ---\n")
t3 <- proc.time()

source("simulation/simple_ryan_white.R")

params <- list(
  adap_suppression_loss = ADAP_LOSS,
  oahs_suppression_loss = OAHS_LOSS,
  other_suppression_loss = OTHER_LOSS
)

intervention <- create_ryan_white_intervention(params)
custom_simset <- run_custom_simulation(base_simset, intervention)

t3_elapsed <- (proc.time() - t3)["elapsed"]
cat(sprintf("  Time: %.1f sec (%.1f min)\n\n", t3_elapsed, t3_elapsed / 60))

# =============================================================================
# Phase 4: Save simsets in batch-compatible layout
# =============================================================================
cat("--- Phase 4: Save simsets ---\n")
t4 <- proc.time()

# Save in the directory layout that batch_plot_generator.R expects:
#   simulations/ryan-white/base/{LOCATION}_base.Rdata
#   simulations/ryan-white/prerun/{LOCATION}/{SCENARIO_KEY}.Rdata
base_dir <- file.path(OUTPUT_DIR, "simulations", "ryan-white", "base")
scenario_dir <- file.path(OUTPUT_DIR, "simulations", "ryan-white", "prerun", LOCATION)
dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(scenario_dir, recursive = TRUE, showWarnings = FALSE)

base_path <- file.path(base_dir, paste0(LOCATION, "_base.Rdata"))
scenario_path <- file.path(scenario_dir, paste0(SCENARIO_KEY, ".Rdata"))

cat(sprintf("  Saving base simset:   %s\n", base_path))
save(base_simset, file = base_path)

cat(sprintf("  Saving custom simset: %s\n", scenario_path))
save(custom_simset, file = scenario_path)

t4_elapsed <- (proc.time() - t4)["elapsed"]
cat(sprintf("  Time: %.1f sec\n\n", t4_elapsed))

# =============================================================================
# Summary
# =============================================================================
total_elapsed <- (proc.time() - total_start)["elapsed"]
cat("===========================================\n")
cat("SIMULATION COMPLETE\n")
cat("===========================================\n")
cat(sprintf("  Phase 1 (workspace):   %6.1f sec\n", t1_elapsed))
cat(sprintf("  Phase 2 (load simset): %6.1f sec\n", t2_elapsed))
cat(sprintf("  Phase 3 (simulation):  %6.1f sec (%.1f min)\n", t3_elapsed, t3_elapsed / 60))
cat(sprintf("  Phase 4 (save):        %6.1f sec\n", t4_elapsed))
cat(sprintf("  TOTAL:                 %6.1f sec (%.1f min)\n", total_elapsed, total_elapsed / 60))
cat(sprintf("  Base simset:           %s\n", base_path))
cat(sprintf("  Custom simset:         %s\n", scenario_path))
cat("===========================================\n")
cat("\nNext step: run batch extraction with:\n")
cat(sprintf("  batch --city %s --scenarios %s --output-mode data ...\n", LOCATION, SCENARIO_KEY))
