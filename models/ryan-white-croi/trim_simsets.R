#!/usr/bin/env Rscript
# trim_simsets.R
# Trims raw simulation sets to web-friendly size
# - Reduces simulations: 1000 -> 80
# - Truncates time range
# - Re-runs simulations with new parameters
#
# Adapted from jheem_analyses/applications/ryan_white/prep_rw_web_simsets.R
# for containerized execution

suppressPackageStartupMessages({
  library(jheem2)
  library(argparse)
})

# =============================================================================
# Configuration (CROI 2026 settings)
# =============================================================================
N_SIM_FOR_WEB <- 80           # Reduce from 1000 to 80 simulations
ANCHOR_YEAR <- 2026           # CROI anchor year
WEB_FROM_YEAR <- ANCHOR_YEAR - 10   # 2016
WEB_TO_YEAR <- ANCHOR_YEAR + 10     # 2036
WEB_SEED_FROM_YEAR <- WEB_FROM_YEAR
WEB_SEED_TO_YEAR <- ANCHOR_YEAR

# CROI intervention codes (from raw file naming)
CROI_INTERVENTION_CODES <- c(
  "noint",           # Baseline (no interruption)
  "rw.end.26",       # Cessation
  "rw.p.intr.26",    # 2.5-year interruption
  "rw.end.cons.26",  # Cessation conservative
  "rw.p.intr.cons.26" # Interruption conservative
)

# =============================================================================
# Argument parsing
# =============================================================================
parser <- ArgumentParser(description = "Trim raw simsets to web-friendly size")
parser$add_argument("--state", type = "character", required = TRUE,
                    help = "State code (e.g., AL, CA, NY)")
parser$add_argument("--input-dir", type = "character", default = "/data/raw",
                    help = "Directory containing raw simset files")
parser$add_argument("--output-dir", type = "character", default = "/data/trimmed",
                    help = "Directory for trimmed output files")
parser$add_argument("--interventions", type = "character", default = "",
                    help = "Comma-separated intervention codes (default: all CROI interventions)")
parser$add_argument("--dry-run", action = "store_true", default = FALSE,
                    help = "Show what would be done without actually trimming")
parser$add_argument("--benchmark", action = "store_true", default = FALSE,
                    help = "Run benchmark mode (trim one file and report timing)")

cli_args <- parser$parse_args()

# =============================================================================
# Setup
# =============================================================================
cat("=== CROI Simset Trimmer ===\n")
cat(sprintf("State: %s\n", cli_args[["state"]]))
cat(sprintf("Input directory: %s\n", cli_args$input_dir))
cat(sprintf("Output directory: %s\n", cli_args$output_dir))
cat(sprintf("Target simulations: %d\n", N_SIM_FOR_WEB))
cat(sprintf("Time range: %d-%d\n", WEB_FROM_YEAR, WEB_TO_YEAR))
cat("\n")

# Load workspace for jheem2 state
cat("Loading workspace...\n")
load("/app/ryan_white_workspace.RData")
cat(sprintf("Workspace loaded with %d objects\n", length(ls())))

# Restore jheem2 internal state
vm <- asNamespace("jheem2")$VERSION.MANAGER
for (name in names(.jheem2_state$version_manager)) {
  assign(name, .jheem2_state$version_manager[[name]], envir = vm)
}
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
for (name in names(.jheem2_state$ontology_mapping_manager)) {
  assign(name, .jheem2_state$ontology_mapping_manager[[name]], envir = ont_mgr)
}
cat("jheem2 state restored\n")

# Restore R6 class generators needed for simulation operations
if ("r6_class_generators" %in% names(.jheem2_state)) {
  for (class_name in names(.jheem2_state$r6_class_generators)) {
    assign(class_name, .jheem2_state$r6_class_generators[[class_name]], envir = .GlobalEnv)
  }
  cat(sprintf("R6 class generators restored: %s\n",
              paste(names(.jheem2_state$r6_class_generators), collapse = ", ")))
} else {
  cat("WARNING: r6_class_generators not found in workspace - simulation operations may fail\n")
}
cat("\n")

# Determine interventions to process
if ("interventions" %in% names(cli_args) && !is.null(cli_args[["interventions"]]) && nchar(cli_args[["interventions"]]) > 0) {
  interventions <- strsplit(cli_args[["interventions"]], ",")[[1]]
} else {
  interventions <- CROI_INTERVENTION_CODES
}

# =============================================================================
# Find input files
# =============================================================================
# Expected naming: rw_final.ehe.state-1000_{STATE}_{intervention}.Rdata
file_pattern <- sprintf("*_%s_*.Rdata", cli_args$state)
input_files <- list.files(cli_args$input_dir, pattern = glob2rx(file_pattern), full.names = TRUE)

if (length(input_files) == 0) {
  cat(sprintf("ERROR: No files found matching pattern '%s' in %s\n", file_pattern, cli_args$input_dir))
  quit(status = 1)
}

cat(sprintf("Found %d input files:\n", length(input_files)))
for (f in input_files) {
  cat(sprintf("  - %s (%.1f MB)\n", basename(f), file.size(f) / 1024^2))
}
cat("\n")

# Create output directory
if (!cli_args$dry_run) {
  dir.create(cli_args$output_dir, recursive = TRUE, showWarnings = FALSE)
}

# =============================================================================
# Process files
# =============================================================================
total_start <- Sys.time()
results <- list()

for (input_file in input_files) {
  filename <- basename(input_file)

  # Extract intervention code from filename
  # Format: rw_final.ehe.state-1000_{STATE}_{intervention}.Rdata
  parts <- strsplit(filename, "_")[[1]]
  intervention <- gsub("\\.Rdata$", "", parts[length(parts)])

  # Check if this intervention should be processed
  if (!intervention %in% interventions) {
    cat(sprintf("SKIP: %s (intervention '%s' not in list)\n", filename, intervention))
    next
  }

  cat(sprintf("=== Processing: %s ===\n", filename))
  cat(sprintf("Intervention: %s\n", intervention))

  if (cli_args$dry_run) {
    cat("  [DRY RUN] Would trim this file\n\n")
    next
  }

  file_start <- Sys.time()

  tryCatch({
    # Step 1: Load raw simset
    cat("  Loading raw simset...\n")
    load_start <- Sys.time()
    loaded_names <- load(input_file)
    full_simset <- get(loaded_names[1])
    load_time <- difftime(Sys.time(), load_start, units = "secs")
    cat(sprintf("    Loaded in %.1f seconds\n", load_time))

    if (!is.null(full_simset$n.sim)) {
      cat(sprintf("    Original simulations: %d\n", full_simset$n.sim))
    }

    # Step 2: Thin to target simulation count
    cat(sprintf("  Thinning to %d simulations...\n", N_SIM_FOR_WEB))
    thin_start <- Sys.time()
    thinned_simset <- full_simset$thin(keep = N_SIM_FOR_WEB)
    thin_time <- difftime(Sys.time(), thin_start, units = "secs")
    cat(sprintf("    Thinned in %.1f seconds\n", thin_time))

    # Step 3: Rerun simulations with truncated time range
    # Use different sub.version and time range for seed vs intervention
    is_seed <- intervention == "noint"
    sub_version <- if (is_seed) "ws" else "w"
    from_year <- if (is_seed) WEB_SEED_FROM_YEAR else WEB_FROM_YEAR
    to_year <- if (is_seed) WEB_SEED_TO_YEAR else WEB_TO_YEAR

    cat(sprintf("  Rerunning simulations (sub.version=%s, %d-%d)...\n",
                sub_version, from_year, to_year))
    rerun_start <- Sys.time()
    web_simset <- rerun.simulations(
      thinned_simset,
      sub.version = sub_version,
      from.year = from_year,
      to.year = to_year,
      verbose = FALSE
    )
    rerun_time <- difftime(Sys.time(), rerun_start, units = "secs")
    cat(sprintf("    Rerun completed in %.1f seconds (%.1f minutes)\n",
                as.numeric(rerun_time), as.numeric(rerun_time) / 60))

    # Step 4: Save trimmed simset
    # Output naming: {STATE}_{intervention}_web.Rdata
    output_filename <- sprintf("%s_%s_web.Rdata", cli_args$state, intervention)
    output_path <- file.path(cli_args$output_dir, output_filename)

    cat(sprintf("  Saving to %s...\n", output_filename))
    save_start <- Sys.time()
    # Note: using save() instead of web_simset$save() for simpler output path control
    simset <- web_simset  # Rename for cleaner saved object
    save(simset, file = output_path)
    save_time <- difftime(Sys.time(), save_start, units = "secs")

    output_size <- file.size(output_path) / 1024^2
    cat(sprintf("    Saved in %.1f seconds (%.1f MB)\n", save_time, output_size))

    # Record results
    file_time <- difftime(Sys.time(), file_start, units = "secs")
    results[[filename]] <- list(
      success = TRUE,
      load_time = as.numeric(load_time),
      thin_time = as.numeric(thin_time),
      rerun_time = as.numeric(rerun_time),
      save_time = as.numeric(save_time),
      total_time = as.numeric(file_time),
      output_size_mb = output_size
    )

    cat(sprintf("  DONE in %.1f seconds\n\n", file_time))

    # In benchmark mode, stop after first file
    if (cli_args$benchmark) {
      cat("=== BENCHMARK MODE: Stopping after first file ===\n")
      break
    }

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n\n", e$message))
    results[[filename]] <<- list(success = FALSE, error = e$message)
  })
}

# =============================================================================
# Summary
# =============================================================================
total_time <- difftime(Sys.time(), total_start, units = "secs")

cat("=== SUMMARY ===\n")
cat(sprintf("Total time: %.1f seconds (%.1f minutes)\n",
            as.numeric(total_time), as.numeric(total_time) / 60))

successful <- sum(sapply(results, function(r) isTRUE(r$success)))
cat(sprintf("Files processed: %d/%d successful\n", successful, length(results)))

if (successful > 0) {
  avg_rerun <- mean(sapply(results[sapply(results, function(r) isTRUE(r$success))],
                           function(r) r$rerun_time))
  cat(sprintf("Average rerun time: %.1f seconds\n", avg_rerun))

  # Extrapolation
  n_interventions <- length(CROI_INTERVENTION_CODES)
  n_states <- 30
  estimated_total <- avg_rerun * n_interventions * n_states
  cat(sprintf("\nExtrapolated total for 30 states:\n"))
  cat(sprintf("  %.1f hours (%.1f minutes per state)\n",
              estimated_total / 3600, (avg_rerun * n_interventions) / 60))
}

cat("\n=== COMPLETE ===\n")
