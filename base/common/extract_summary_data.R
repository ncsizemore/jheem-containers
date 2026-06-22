#!/usr/bin/env Rscript

# extract_summary_data.R
# Extracts summary data from JHEEM simsets and data managers for native frontend plotting
# Outputs JSON files containing pre-aggregated arrays at finest granularity

suppressPackageStartupMessages({
  library(jheem2)
  library(jsonlite)
  library(reshape2)
  library(argparse)
})

# Export jheem2 internal functions
pkg_env <- asNamespace("jheem2")
internal_fns <- ls(pkg_env, all.names = TRUE)
for (fn in internal_fns) {
  if (exists(fn, pkg_env, inherits = FALSE) && is.function(get(fn, pkg_env))) {
    assign(fn, get(fn, pkg_env), envir = .GlobalEnv)
  }
}

# Load workspace
cat("Loading workspace data...\n")
load("ryan_white_workspace.RData")
cat("Workspace loaded with", length(ls()), "objects\n")

# Restore jheem2 internal state
vm <- asNamespace("jheem2")$VERSION.MANAGER
for (name in names(.jheem2_state$version_manager)) {
  assign(name, .jheem2_state$version_manager[[name]], envir = vm)
}
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
for (name in names(.jheem2_state$ontology_mapping_manager)) {
  assign(name, .jheem2_state$ontology_mapping_manager[[name]], envir = ont_mgr)
}

# Set up data manager
get.default.data.manager <- function() {
  if (exists("WEB.DATA.MANAGER", envir = .GlobalEnv)) {
    return(WEB.DATA.MANAGER)
  } else if (exists("RW.DATA.MANAGER", envir = .GlobalEnv)) {
    return(RW.DATA.MANAGER)
  } else {
    warning("No data manager found")
    return(NULL)
  }
}

#' Extract summary data from a simset at finest granularity
#' @param simset A jheem.simulation.set object
#' @param outcomes Character vector of outcomes to extract
#' @param dimensions Character vector of dimensions to keep (e.g., c("age", "sex", "race"))
#' @param summary.type One of "mean.and.interval" or "median.and.interval"
#' @return List with extracted data for each outcome
extract_simset_data <- function(simset,
                                 outcomes = NULL,
                                 dimensions = c("age", "sex", "race"),
                                 summary.type = "mean.and.interval") {

  if (is.null(outcomes)) {
    outcomes <- setdiff(simset$outcomes, c("infected", "uninfected"))
  }

  result <- list()

  for (outcome in outcomes) {
    cat(sprintf("  Extracting outcome: %s\n", outcome))

    tryCatch({
      # Get data at finest granularity (all dimensions kept)
      keep.dimensions <- c("year", dimensions)

      raw_data <- simset$get(
        outcomes = outcome,
        dimension.values = list(),
        keep.dimensions = keep.dimensions,
        drop.single.outcome.dimension = TRUE,
        mapping = NULL,
        summary.type = summary.type
      )

      if (is.null(raw_data)) {
        cat(sprintf("    WARNING: No data returned for %s\n", outcome))
        next
      }

      # Get metadata
      outcome_meta <- simset$outcome.metadata[[outcome]]
      display_as_percent <- isTRUE(outcome_meta$display.as.percent)

      # Apply percent conversion if needed
      if (display_as_percent) {
        raw_data <- raw_data * 100
      }

      # Melt to long format
      df <- reshape2::melt(raw_data, na.rm = TRUE)
      df <- as.data.frame(lapply(df, function(col) {
        if (is.factor(col)) as.character(col) else col
      }))

      # Reshape wide to get mean, lower, upper as columns
      if ("metric" %in% names(df)) {
        id_vars <- setdiff(names(df), c("metric", "value"))
        df_wide <- reshape(df, direction = "wide", idvar = id_vars, timevar = "metric")

        # Standardize column names
        if ("value.mean" %in% names(df_wide)) {
          df_wide$value <- df_wide$value.mean
        } else if ("value.median" %in% names(df_wide)) {
          df_wide$value <- df_wide$value.median
        }
        df <- df_wide
      }

      # Build result structure
      result[[outcome]] <- list(
        metadata = list(
          display_name = outcome_meta$display.name,
          units = outcome_meta$units,
          display_as_percent = display_as_percent,
          axis_name = outcome_meta$axis.name %||% outcome_meta$display.name
        ),
        data = df
      )

      cat(sprintf("    Extracted %d rows\n", nrow(df)))

    }, error = function(e) {
      cat(sprintf("    ERROR extracting %s: %s\n", outcome, e$message))
    })
  }

  return(result)
}

#' Extract observation data from data manager at multiple granularities
#'
#' This function pulls observation data at ALL available granularities:
#' - year-only: For unfaceted aggregate views (gets ALL years including pre-2017)
#' - year+age: For age-faceted views (where available, typically 2017+)
#' - year+sex: For sex-faceted views (where available)
#' - year+race: For race-faceted views (where available)
#'
#' This ensures the frontend has the right data for both aggregate and faceted views.
#'
#' See: .claude-sessions/2025-12-14_observation_data_investigation.md for full analysis.
#'
#' @param data.manager A jheem.data.manager object
#' @param simset_outcomes Character vector of simset outcomes
#' @param outcome_mappings Named list mapping simset outcomes to data manager outcomes
#' @param location Location code (e.g., "C.12580")
#' @return List with observation data at multiple granularities (keyed by simset outcome name)
extract_observation_data <- function(data.manager,
                                      simset_outcomes,
                                      outcome_mappings,
                                      location) {

  result <- list()
  dm_outcomes <- names(data.manager$outcome.info)

  # Define granularities to pull - order matters for logging but all are independent
  granularities <- list(
    list(name = "year", dims = c("year")),
    list(name = "year_age", dims = c("year", "age")),
    list(name = "year_sex", dims = c("year", "sex")),
    list(name = "year_race", dims = c("year", "race"))
  )

  for (simset_outcome in simset_outcomes) {
    # Get the corresponding data manager outcome name
    dm_outcome <- outcome_mappings[[simset_outcome]]

    if (is.null(dm_outcome) || dm_outcome == "NULL") {
      cat(sprintf("  %s: No corresponding observed outcome mapped\n", simset_outcome))
      next
    }

    if (!(dm_outcome %in% dm_outcomes)) {
      cat(sprintf("  %s -> %s: Not registered in data manager\n", simset_outcome, dm_outcome))
      next
    }

    cat(sprintf("  Extracting observations: %s -> %s\n", simset_outcome, dm_outcome))

    # Get metadata from data manager
    outcome_info <- data.manager$outcome.info[[dm_outcome]]
    display_as_percent <- isTRUE(outcome_info$metadata$display.as.percent)

    # Pull at each granularity
    data_by_granularity <- list()
    available_granularities <- c()

    for (gran in granularities) {
      obs_data <- tryCatch({
        data.manager$pull(
          outcome = dm_outcome,
          dimension.values = list(location = location),
          keep.dimensions = gran$dims,
          na.rm = TRUE,
          append.attributes = "url"
        )
      }, error = function(e) {
        NULL
      })

      if (is.null(obs_data) || length(obs_data) == 0) {
        next
      }

      # Apply percent conversion if needed
      if (display_as_percent) {
        obs_data <- obs_data * 100
      }

      # Melt to long format
      df <- tryCatch({
        reshape2::melt(obs_data, na.rm = TRUE, as.is = TRUE)
      }, error = function(e) {
        NULL
      })

      if (is.null(df) || nrow(df) == 0) {
        next
      }

      # Attach source info (it's typically in dimnames after melt)
      # The source column should already be present from the melt if it was a dimension

      data_by_granularity[[gran$name]] <- df
      available_granularities <- c(available_granularities, gran$name)
      cat(sprintf("    %s: %d points\n", gran$name, nrow(df)))
    }

    if (length(data_by_granularity) == 0) {
      cat(sprintf("    No observations found at any granularity\n"))
      next
    }

    # Store under the SIMSET outcome name for consistency with simulation data
    result[[simset_outcome]] <- list(
      metadata = list(
        simset_outcome = simset_outcome,
        data_manager_outcome = dm_outcome,
        display_name = outcome_info$metadata$display.name,
        units = outcome_info$metadata$units,
        display_as_percent = display_as_percent,
        available_granularities = available_granularities
      ),
      data = data_by_granularity
    )
  }

  return(result)
}

#' Build complete export structure for a city
#' @param city City code
#' @param scenarios Vector of scenario names
#' @param outcomes Vector of outcomes (NULL for all)
#' @param base_sim_path Path to base simulations
#' @param prerun_sim_path Path to prerun simulations
#' @return Complete data structure for JSON export
build_city_export <- function(city,
                               scenarios = c("cessation", "brief_interruption", "prolonged_interruption"),
                               outcomes = NULL,
                               base_sim_path = "simulations/ryan-white/base",
                               prerun_sim_path = "simulations/ryan-white/prerun") {

  cat(sprintf("\n=== Processing city: %s ===\n", city))

  data.manager <- get.default.data.manager()

  # Load baseline simulation
  baseline_file <- file.path(base_sim_path, paste0(city, "_base.Rdata"))
  if (!file.exists(baseline_file)) {
    stop(sprintf("Baseline simulation not found: %s", baseline_file))
  }

  cat("Loading baseline simulation...\n")
  baseline_env <- new.env()
  load(baseline_file, envir = baseline_env)
  baseline_objects <- ls(baseline_env)
  simset_objects <- baseline_objects[grepl("simset", baseline_objects, ignore.case = TRUE)]
  if (length(simset_objects) == 0) simset_objects <- baseline_objects
  baseline_simset <- get(simset_objects[1], envir = baseline_env)
  cat(sprintf("  Loaded baseline simset: %s\n", simset_objects[1]))

  # Determine outcomes if not specified
  if (is.null(outcomes)) {
    outcomes <- setdiff(baseline_simset$outcomes, c("infected", "uninfected"))
  }

  # Build outcome mappings (simset outcome -> data manager outcome)
  outcome_mappings <- list()
  for (outcome in outcomes) {
    meta <- baseline_simset$outcome.metadata[[outcome]]
    corresponding <- meta$corresponding.observed.outcome
    outcome_mappings[[outcome]] <- if (is.null(corresponding)) "NULL" else corresponding
  }
  cat("Outcome mappings (simset -> data manager):\n")
  for (outcome in outcomes) {
    cat(sprintf("  %s -> %s\n", outcome, outcome_mappings[[outcome]]))
  }

  # Get dimension info from simset
  # This gives us the actual values for each dimension
  dimensions_info <- list()
  for (dim_name in c("age", "sex", "race")) {
    tryCatch({
      # Try to get dimension values from the ontology
      ontology <- baseline_simset$outcome.ontologies[[outcomes[1]]]
      if (!is.null(ontology) && dim_name %in% names(ontology)) {
        dimensions_info[[dim_name]] <- list(
          values = ontology[[dim_name]],
          label = dim_name
        )
      }
    }, error = function(e) {
      cat(sprintf("Could not get dimension info for %s: %s\n", dim_name, e$message))
    })
  }

  # Build metadata
  metadata <- list(
    city = city,
    city_label = tryCatch(
      locations::get.location.name(city),
      error = function(e) city
    ),
    scenarios = scenarios,
    outcomes = lapply(outcomes, function(o) {
      meta <- baseline_simset$outcome.metadata[[o]]
      list(
        id = o,
        display_name = meta$display.name,
        units = meta$units,
        display_as_percent = isTRUE(meta$display.as.percent),
        corresponding_observed_outcome = outcome_mappings[[o]]
      )
    }),
    dimensions = dimensions_info,
    generation_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
  )
  names(metadata$outcomes) <- outcomes

  # Extract simulation data for each scenario
  simulations <- list()

  for (scenario in scenarios) {
    cat(sprintf("\nProcessing scenario: %s\n", scenario))

    scenario_file <- file.path(prerun_sim_path, city, paste0(scenario, ".Rdata"))
    if (!file.exists(scenario_file)) {
      cat(sprintf("  WARNING: Scenario file not found: %s\n", scenario_file))
      next
    }

    # Load scenario into a fresh environment to avoid name collisions
    scenario_env <- new.env()
    load(scenario_file, envir = scenario_env)

    # Get the simset object from the fresh environment (should be only object, or first simset-like one)
    scenario_objects <- ls(scenario_env)
    simset_objects <- scenario_objects[grepl("simset", scenario_objects, ignore.case = TRUE)]
    if (length(simset_objects) == 0) {
      # Fallback: take the first object if no simset found
      simset_objects <- scenario_objects
    }
    if (length(simset_objects) == 0) {
      cat(sprintf("  WARNING: No objects found in %s\n", scenario_file))
      next
    }
    scenario_simset <- get(simset_objects[1], envir = scenario_env)
    cat(sprintf("  Loaded scenario simset: %s\n", simset_objects[1]))

    simulations[[scenario]] <- list(
      baseline = extract_simset_data(baseline_simset, outcomes),
      intervention = extract_simset_data(scenario_simset, outcomes)
    )
  }

  # Extract observation data using the outcome mappings
  cat("\nExtracting observation data...\n")
  observations <- extract_observation_data(
    data.manager = data.manager,
    simset_outcomes = outcomes,
    outcome_mappings = outcome_mappings,
    location = city
  )

  # Assemble final structure
  export_data <- list(
    metadata = metadata,
    simulations = simulations,
    observations = observations,
    export_info = list(
      exported_on = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
      format_version = "1.0"
    )
  )

  return(export_data)
}

#' Convert export structure to JSON-friendly format
#' Converts data frames to arrays organized by dimension
prepare_for_json <- function(export_data) {

  # Helper to convert df to nested structure
  df_to_nested <- function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)

    # Get dimension columns (everything except year, value, value.lower, value.upper, etc.)
    value_cols <- c("value", "value.lower", "value.upper", "value.mean", "value.median", "url", "source")
    dim_cols <- setdiff(names(df), c("year", value_cols))

    if (length(dim_cols) == 0) {
      # No dimensions - just return array of year/value pairs
      result <- lapply(seq_len(nrow(df)), function(i) {
        row_data <- list(year = df$year[i], value = df$value[i])
        if ("value.lower" %in% names(df)) row_data$lower <- df$value.lower[i]
        if ("value.upper" %in% names(df)) row_data$upper <- df$value.upper[i]
        if ("url" %in% names(df)) row_data$url <- df$url[i]
        if ("source" %in% names(df)) row_data$source <- df$source[i]
        row_data
      })
      return(result)
    }

    # Create strata key from dimension columns
    df$stratum_key <- apply(df[, dim_cols, drop = FALSE], 1, paste, collapse = "_")

    # Group by stratum
    strata <- split(df, df$stratum_key)

    result <- lapply(strata, function(stratum_df) {
      lapply(seq_len(nrow(stratum_df)), function(i) {
        row_data <- list(year = stratum_df$year[i], value = stratum_df$value[i])
        if ("value.lower" %in% names(stratum_df)) row_data$lower <- stratum_df$value.lower[i]
        if ("value.upper" %in% names(stratum_df)) row_data$upper <- stratum_df$value.upper[i]
        if ("url" %in% names(stratum_df)) row_data$url <- stratum_df$url[i]
        if ("source" %in% names(stratum_df)) row_data$source <- stratum_df$source[i]
        row_data
      })
    })

    return(result)
  }

  # Process simulations
  for (scenario in names(export_data$simulations)) {
    for (sim_type in c("baseline", "intervention")) {
      if (!is.null(export_data$simulations[[scenario]][[sim_type]])) {
        for (outcome in names(export_data$simulations[[scenario]][[sim_type]])) {
          df <- export_data$simulations[[scenario]][[sim_type]][[outcome]]$data
          export_data$simulations[[scenario]][[sim_type]][[outcome]]$data <- df_to_nested(df)
        }
      }
    }
  }

  # Process observations - now with multi-granularity structure
  for (outcome in names(export_data$observations)) {
    obs_data <- export_data$observations[[outcome]]$data
    # obs_data is now a list keyed by granularity (year, year_age, year_sex, year_race)
    for (gran_name in names(obs_data)) {
      df <- obs_data[[gran_name]]
      export_data$observations[[outcome]]$data[[gran_name]] <- df_to_nested(df)
    }
  }

  return(export_data)
}

# Main execution
main <- function() {
  parser <- ArgumentParser(description = "Extract summary data for native frontend plotting")
  parser$add_argument("--city", type = "character", required = TRUE, help = "City code (e.g., C.12580)")
  parser$add_argument("--scenarios", type = "character", default = "cessation,brief_interruption,prolonged_interruption",
                      help = "Comma-separated scenarios")
  parser$add_argument("--outcomes", type = "character", default = NULL,
                      help = "Comma-separated outcomes (default: all)")
  parser$add_argument("--output", type = "character", default = NULL,
                      help = "Output JSON file (default: {city}_summary.json)")
  parser$add_argument("--raw", action = "store_true", default = FALSE,
                      help = "Output raw data frames instead of nested structure")

  args <- parser$parse_args()

  scenarios <- trimws(strsplit(args$scenarios, ",")[[1]])
  outcomes <- if (!is.null(args$outcomes)) trimws(strsplit(args$outcomes, ",")[[1]]) else NULL
  output_file <- if (!is.null(args$output)) args$output else paste0(args$city, "_summary.json")

  # Extract data
  export_data <- build_city_export(
    city = args$city,
    scenarios = scenarios,
    outcomes = outcomes
  )

  # Prepare for JSON (unless raw output requested)
  if (!args$raw) {
    export_data <- prepare_for_json(export_data)
  }

  # Write JSON
  cat(sprintf("\nWriting output to: %s\n", output_file))
  json_output <- toJSON(export_data, auto_unbox = TRUE, pretty = TRUE, na = "null")
  writeLines(json_output, output_file)

  # Report stats
  file_size <- file.info(output_file)$size
  cat(sprintf("Output file size: %.2f KB (%.2f MB)\n", file_size / 1024, file_size / (1024 * 1024)))

  cat("\nExtraction complete!\n")
}

# Run if executed directly (with command line args)
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  main()
}
