#!/usr/bin/env Rscript

# =============================================================================
# custom_simulation.R
# =============================================================================
# Runs a custom simulation with user-specified parameters and extracts data
# in the same JSON format as batch mode (for portal consumption).
#
# Pipeline:
#   1. Load workspace + restore jheem2 state
#   2. Load base simset
#   3. Create intervention with user parameters
#   4. Run forward simulation
#   5. Extract outcome data as per-combination JSON files
#      (same format as batch_plot_generator.R --output-mode data)
#
# Environment variables:
#   LOCATION        - Location code (e.g., "AL", "C.12580")
#   SCENARIO_KEY    - Deterministic key from params (e.g., "a50-o30-r40")
#   SCENARIO_LABEL  - Human-readable label for chart legends
#   ADAP_LOSS       - ADAP suppression loss % (default: 50)
#   OAHS_LOSS       - OAHS suppression loss % (default: 30)
#   OTHER_LOSS      - Other suppression loss % (default: 40)
#   OUTCOMES        - Comma-separated outcomes (default: all from model)
#   STATISTICS      - Comma-separated statistics (default: mean.and.interval,median.and.interval)
#   FACETS          - Comma-separated facets (default: none,age,race,sex,risk)
#   OUTPUT_DIR      - Output directory (default: /output)
#
# SCENARIO_KEY and SCENARIO_LABEL are derived from models.json parameter
# definitions by the workflow. The key ensures identical parameters always
# produce the same S3 path for caching.
# =============================================================================

total_start <- proc.time()

cat("===========================================\n")
cat("CUSTOM SIMULATION PIPELINE\n")
cat("===========================================\n\n")

# --- Parse configuration from environment ---
LOCATION <- Sys.getenv("LOCATION", "AL")
ADAP_LOSS <- as.numeric(Sys.getenv("ADAP_LOSS", "50"))
OAHS_LOSS <- as.numeric(Sys.getenv("OAHS_LOSS", "30"))
OTHER_LOSS <- as.numeric(Sys.getenv("OTHER_LOSS", "40"))
OUTPUT_DIR <- Sys.getenv("OUTPUT_DIR", "/output")

# Scenario key and label are derived from models.json parameter definitions
# by the workflow and passed as env vars. Fallback to parameter-derived defaults.
SCENARIO_KEY <- Sys.getenv("SCENARIO_KEY", sprintf("a%g-o%g-r%g", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))
SCENARIO_LABEL <- Sys.getenv("SCENARIO_LABEL", sprintf("ADAP %g%%, OAHS %g%%, Other %g%%", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))

OUTCOMES_ENV <- Sys.getenv("OUTCOMES", "")
STATISTICS_ENV <- Sys.getenv("STATISTICS", "mean.and.interval,median.and.interval")
FACETS_ENV <- Sys.getenv("FACETS", "none,age,race,sex,risk")

# Parse comma-separated lists
statistics <- strsplit(STATISTICS_ENV, ",")[[1]]
facets_raw <- strsplit(FACETS_ENV, ",")[[1]]

# Convert facet strings to the format batch_plot_generator expects
# "none" -> NULL, "age" -> "age", "age+race" -> c("age", "race")
facets <- lapply(facets_raw, function(f) {
  if (f == "none") return(NULL)
  strsplit(f, "\\+")[[1]]
})

cat(sprintf("  Location:       %s\n", LOCATION))
cat(sprintf("  Scenario key:   %s\n", SCENARIO_KEY))
cat(sprintf("  Scenario label: %s\n", SCENARIO_LABEL))
cat(sprintf("  Parameters:     ADAP=%g%%, OAHS=%g%%, Other=%g%%\n", ADAP_LOSS, OAHS_LOSS, OTHER_LOSS))
cat(sprintf("  Statistics:     %s\n", paste(statistics, collapse = ", ")))
cat(sprintf("  Facets:         %s\n", paste(facets_raw, collapse = ", ")))
cat(sprintf("  Output:         %s\n", OUTPUT_DIR))
cat("\n")

# =============================================================================
# Phase 1: Load workspace and dependencies
# =============================================================================
cat("--- Phase 1: Load workspace ---\n")
t1 <- proc.time()

suppressPackageStartupMessages({
  library(jheem2)
  library(jsonlite)
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

# Source plotting/extraction dependencies (same as batch_plot_generator.R)
source("plotting/plotting_deps/simplot_local_mods.R")
source("plotting/plotting_deps/plotting_local.R")
source("plotting/plotting_deps/load_config.R")
source("plotting/plotting_deps/plot_panel.R")
source("plotting/plotting_deps/plot_data_preparation.R")
source("plotting/plotting_deps/plot_rendering.R")
source("plotting/plotting_deps/baseline_loading.R")

# Data manager function (same as batch_plot_generator.R)
get.default.data.manager <- function() {
  if (exists("WEB.DATA.MANAGER", envir = .GlobalEnv)) return(WEB.DATA.MANAGER)
  if (exists("RW.DATA.MANAGER", envir = .GlobalEnv)) return(RW.DATA.MANAGER)
  if (exists("CDCT.DATA.MANAGER", envir = .GlobalEnv)) return(CDCT.DATA.MANAGER)
  warning("No data manager found in workspace")
  NULL
}

t1_elapsed <- (proc.time() - t1)["elapsed"]
cat(sprintf("  Time: %.1f sec\n\n", t1_elapsed))

# =============================================================================
# Phase 2: Load base simset
# =============================================================================
cat("--- Phase 2: Load base simset ---\n")
t2 <- proc.time()

# Find simset file — prefer one matching LOCATION, fall back to first .Rdata
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
# Phase 4: Extract data (same format as batch mode)
# =============================================================================
cat("--- Phase 4: Extract outcome data ---\n")
t4 <- proc.time()

# Resolve outcomes: use env var or extract from simset
if (OUTCOMES_ENV != "") {
  outcomes <- strsplit(OUTCOMES_ENV, ",")[[1]]
} else {
  # Try to get outcome names from the simset
  outcomes <- tryCatch({
    # Get all fields that aren't methods
    all_fields <- ls(custom_simset)
    known_outcomes <- c(
      "incidence", "diagnosed.prevalence", "suppression", "testing",
      "prep.uptake", "awareness", "rw.clients", "adap.clients",
      "non.adap.clients", "oahs.clients", "adap.proportion",
      "oahs.suppression", "adap.suppression", "new"
    )
    # Use known outcomes that exist in the simset
    known_outcomes[known_outcomes %in% all_fields]
  }, error = function(e) {
    c("incidence", "diagnosed.prevalence", "suppression")
  })
}
cat(sprintf("  Outcomes: %s (%d)\n", paste(outcomes, collapse = ", "), length(outcomes)))

# Use scenario key as directory name (already filesystem-safe)
scenario_id <- SCENARIO_KEY

# generate_paths function (from batch_plot_generator.R)
generate_paths <- function(city, scenario, outcome, statistic, facet_spec, output_dir) {
  city_dir <- file.path(output_dir, city)
  scenario_dir <- file.path(city_dir, scenario)
  if (!dir.exists(scenario_dir)) {
    dir.create(scenario_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (is.null(facet_spec)) {
    facet_part <- "unfaceted"
  } else if (length(facet_spec) == 1) {
    facet_part <- paste0("facet_", facet_spec)
  } else {
    facet_part <- paste0("facet_", paste(facet_spec, collapse = "+"))
  }

  base_name <- paste0(outcome, "_", statistic, "_", facet_part)

  list(
    json = file.path(scenario_dir, paste0(base_name, ".json")),
    metadata = file.path(scenario_dir, paste0(base_name, "_metadata.json")),
    html = file.path(scenario_dir, paste0(base_name, ".html"))
  )
}

# generate_data_output function (from batch_plot_generator.R)
generate_data_output <- function(city, scenario, outcome, statistic, facet_spec,
                                 scenario_simset, baseline_simset, config, output_dir) {
  tryCatch(
    {
      intervention_label <- if (!is.null(config) && !is.null(config[[scenario]])) {
        config[[scenario]]$label %||% scenario
      } else {
        scenario
      }

      sim_list <- list()
      if (!is.null(baseline_simset)) {
        sim_list[["Baseline"]] <- baseline_simset
      }
      sim_list[[intervention_label]] <- scenario_simset

      data_manager <- get.default.data.manager()

      prepared_data <- prepare_plot_local(
        simset.list = sim_list,
        outcomes = outcome,
        facet.by = facet_spec,
        data.manager = data_manager,
        summary.type = statistic,
        plot.which = "sim.and.data",
        append.url = TRUE,
        show.data.pull.error = FALSE
      )

      # Extract simulation data columns
      sim_data <- NULL
      if (!is.null(prepared_data$df.sim) && nrow(prepared_data$df.sim) > 0) {
        sim_cols <- c("year", "value", "simset", "outcome", "outcome.display.name")
        if ("value.lower" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "value.lower", "value.upper")
        facet_cols <- grep("^facet\\.by[0-9]+$", names(prepared_data$df.sim), value = TRUE)
        if (length(facet_cols) > 0) sim_cols <- c(sim_cols, facet_cols)
        if ("stratum" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "stratum")
        if ("sim" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "sim")
        sim_cols <- intersect(sim_cols, names(prepared_data$df.sim))
        sim_data <- prepared_data$df.sim[, sim_cols, drop = FALSE]
      }

      # Extract observation data columns
      obs_data <- NULL
      if (!is.null(prepared_data$df.truth) && nrow(prepared_data$df.truth) > 0) {
        obs_cols <- c("year", "value", "source", "outcome", "outcome.display.name")
        facet_cols_obs <- grep("^facet\\.by[0-9]+$", names(prepared_data$df.truth), value = TRUE)
        if (length(facet_cols_obs) > 0) obs_cols <- c(obs_cols, facet_cols_obs)
        if ("data_url" %in% names(prepared_data$df.truth)) obs_cols <- c(obs_cols, "data_url")
        if ("stratum" %in% names(prepared_data$df.truth)) obs_cols <- c(obs_cols, "stratum")
        obs_cols <- intersect(obs_cols, names(prepared_data$df.truth))
        obs_data <- prepared_data$df.truth[, obs_cols, drop = FALSE]
      }

      output_data <- list(
        sim = sim_data,
        obs = obs_data,
        metadata = list(
          city = city,
          scenario = scenario,
          outcome = outcome,
          statistic = statistic,
          facet = if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+"),
          y_label = prepared_data$details$y.label,
          plot_title = prepared_data$details$plot.title,
          has_baseline = !is.null(baseline_simset),
          generation_time = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        )
      )

      if (!is.null(prepared_data$details$outcome.metadata.list[[outcome]])) {
        output_data$metadata$outcome_metadata <- list(
          display_name = prepared_data$details$outcome.metadata.list[[outcome]]$display.name,
          units = prepared_data$details$outcome.metadata.list[[outcome]]$units,
          display_as_percent = prepared_data$details$outcome.metadata.list[[outcome]]$display.as.percent
        )
      }

      paths <- generate_paths(city, scenario, outcome, statistic, facet_spec, output_dir)
      writeLines(toJSON(output_data, auto_unbox = TRUE, pretty = TRUE, na = "null"), paths$json)

      list(success = TRUE, paths = paths)
    },
    error = function(e) {
      list(success = FALSE, error = e$message)
    }
  )
}

# Scenario config for the intervention label
scenario_config <- list()
scenario_config[[scenario_id]] <- list(label = SCENARIO_LABEL)

# Run extraction for all combinations
total_combos <- length(outcomes) * length(statistics) * length(facets)
cat(sprintf("  Extracting %d combinations (%d outcomes × %d statistics × %d facets)\n",
            total_combos, length(outcomes), length(statistics), length(facets)))

combo_count <- 0
success_count <- 0
error_count <- 0

for (outcome in outcomes) {
  for (statistic in statistics) {
    for (facet_spec in facets) {
      combo_count <- combo_count + 1
      facet_str <- if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+")

      result <- generate_data_output(
        city = LOCATION,
        scenario = scenario_id,
        outcome = outcome,
        statistic = statistic,
        facet_spec = facet_spec,
        scenario_simset = custom_simset,
        baseline_simset = base_simset,
        config = scenario_config,
        output_dir = OUTPUT_DIR
      )

      if (result$success) {
        success_count <- success_count + 1
        cat(sprintf("  [%d/%d] OK: %s/%s/%s\n", combo_count, total_combos, outcome, statistic, facet_str))
      } else {
        error_count <- error_count + 1
        cat(sprintf("  [%d/%d] FAIL: %s/%s/%s - %s\n", combo_count, total_combos, outcome, statistic, facet_str, result$error))
      }
    }
  }
}

t4_elapsed <- (proc.time() - t4)["elapsed"]
cat(sprintf("  Time: %.1f sec\n\n", t4_elapsed))

# =============================================================================
# Summary
# =============================================================================
total_elapsed <- (proc.time() - total_start)["elapsed"]
cat("===========================================\n")
cat("PIPELINE COMPLETE\n")
cat("===========================================\n")
cat(sprintf("  Phase 1 (workspace):   %6.1f sec\n", t1_elapsed))
cat(sprintf("  Phase 2 (load simset): %6.1f sec\n", t2_elapsed))
cat(sprintf("  Phase 3 (simulation):  %6.1f sec (%.1f min)\n", t3_elapsed, t3_elapsed / 60))
cat(sprintf("  Phase 4 (extraction):  %6.1f sec\n", t4_elapsed))
cat(sprintf("  TOTAL:                 %6.1f sec (%.1f min)\n", total_elapsed, total_elapsed / 60))
cat(sprintf("  Files generated:       %d / %d\n", success_count, total_combos))
if (error_count > 0) {
  cat(sprintf("  Errors:                %d\n", error_count))
}
cat(sprintf("  Output directory:      %s\n", OUTPUT_DIR))
cat("===========================================\n")

if (error_count > 0 && success_count == 0) {
  quit(status = 1)
}
