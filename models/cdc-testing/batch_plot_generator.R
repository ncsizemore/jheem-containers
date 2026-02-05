#!/usr/bin/env Rscript

# batch_plot_generator.R
# Efficient batch plot generation with simulation reuse
# Generates all combinations of outcomes/statistics/facets for loaded simulations
# CONTAINER VERSION: Adapted to work with container's plotting dependencies

# Load necessary libraries (done once at startup)
suppressPackageStartupMessages({
  library(plotly)
  library(jheem2)
  library(argparse)
  library(yaml)
  library(ggplot2)
  library(htmlwidgets)
  library(jsonlite)
  library(locations)
})

# Export all jheem2 internal functions to the global environment (done once)
pkg_env <- asNamespace("jheem2")
internal_fns <- ls(pkg_env, all.names = TRUE)
for (fn in internal_fns) {
  if (exists(fn, pkg_env, inherits = FALSE) && is.function(get(fn, pkg_env))) {
    assign(fn, get(fn, pkg_env), envir = .GlobalEnv)
  }
}

# CONTAINER MODIFICATION: Use workspace data instead of sourcing ryan_white_specification.R
cat("Loading workspace data...\n")
load("ryan_white_workspace.RData")
cat("✅ Workspace loaded with", length(ls()), "objects\n")
cat("✅ RW.SPECIFICATION available:", exists("RW.SPECIFICATION"), "\n")
cat("✅ RW.DATA.MANAGER available:", exists("RW.DATA.MANAGER"), "\n")

# CONTAINER MODIFICATION: Restore jheem2 internal state from workspace
# Restore VERSION.MANAGER
vm <- asNamespace("jheem2")$VERSION.MANAGER  
for (name in names(.jheem2_state$version_manager)) {
  assign(name, .jheem2_state$version_manager[[name]], envir = vm)
}

# Restore ONTOLOGY.MAPPING.MANAGER using consistent approach
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
for (name in names(.jheem2_state$ontology_mapping_manager)) {
  assign(name, .jheem2_state$ontology_mapping_manager[[name]], envir = ont_mgr)
}

# CONTAINER MODIFICATION: Set up data manager function
# This ensures we use the correct data manager from the workspace
get.default.data.manager <- function() {
  # Container prioritizes WEB.DATA.MANAGER for real-world data points
  # but keeps RW.DATA.MANAGER as fallback for compatibility
  if (exists("WEB.DATA.MANAGER", envir = .GlobalEnv)) {
    return(WEB.DATA.MANAGER)
  } else if (exists("RW.DATA.MANAGER", envir = .GlobalEnv)) {
    return(RW.DATA.MANAGER)
  } else {
    warning("No data manager found in workspace (checked WEB.DATA.MANAGER, RW.DATA.MANAGER)")
    return(NULL)
  }
}

# Source required utils and components (done once)
tryCatch(
  {
    # CONTAINER MODIFICATION: Adjust paths for container directory structure
    source("plotting/plotting_deps/simplot_local_mods.R")
    source("plotting/plotting_deps/plotting_local.R")
    source("plotting/plotting_deps/load_config.R")
    source("plotting/plotting_deps/plot_panel.R")
    source("plotting/plotting_deps/plot_data_preparation.R")
    source("plotting/plotting_deps/plot_rendering.R")
    source("plotting/plotting_deps/baseline_loading.R")
  },
  error = function(e) {
    cat(sprintf("ERROR: Failed to source required files: %s\n", e$message))
    quit(status = 1)
  }
)

# Logging function
log_msg <- function(message, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] %s: %s\n", timestamp, level, message))
}

# Create argument parser
parser <- ArgumentParser(description = "Batch plot generator with simulation reuse")
parser$add_argument("--city", type = "character", help = "City to process (e.g., C.12580)")
parser$add_argument("--scenario", type = "character", help = "Single scenario (e.g., cessation)")
parser$add_argument("--scenarios", type = "character", help = "Comma-separated scenarios (e.g., cessation,brief_interruption)")
parser$add_argument("--outcomes", type = "character", required = FALSE, help = "Comma-separated outcomes (e.g., incidence,diagnosed.prevalence)")
parser$add_argument("--statistics", type = "character", default = "mean.and.interval", help = "Comma-separated statistics (default: mean.and.interval)")
parser$add_argument("--facets", type = "character", default = "sex", help = "Comma-separated facet combinations (e.g., sex,age,race,sex+age)")
parser$add_argument("--config", type = "character", help = "YAML config file (alternative to individual parameters)")
parser$add_argument("--output-dir", type = "character", default = "plots", help = "Output directory (default: plots)")
parser$add_argument("--skip-existing", action = "store_true", default = FALSE, help = "Skip plots that already exist")
parser$add_argument("--dry-run", action = "store_true", default = FALSE, help = "Show what would be generated without actually generating")
parser$add_argument("--upload-s3", action = "store_true", default = FALSE, help = "Upload generated JSON files to S3")
parser$add_argument("--register-db", action = "store_true", default = FALSE, help = "Register plot metadata in DynamoDB via API")
parser$add_argument("--s3-bucket", type = "character", default = "prerun-plots-bucket-local", help = "S3 bucket name")
parser$add_argument("--api-gateway-id", type = "character", help = "API Gateway ID for database registration")
parser$add_argument("--api-base-url", type = "character", help = "Full API base URL (alternative to api-gateway-id)")
parser$add_argument("--json-only", action = "store_true", default = TRUE, help = "Generate only JSON files (default: true for production)")
parser$add_argument("--include-html", action = "store_true", default = FALSE, help = "Also generate HTML files (for development/testing)")
parser$add_argument("--output-mode", type = "character", default = "plot", help = "Output mode: 'plot' (default) for Plotly JSON, 'data' for raw data frames")

# Parse arguments
args <- parser$parse_args()

# Debug mode (uncomment for local testing)
# debug_args <- c("--city", "C.12580", "--scenarios", "cessation", "--outcomes", "testing", "--facets", "sex", "--statistics", "mean.and.interval", "--include-html")
# args <- parser$parse_args(debug_args)

# Parse comma-separated values
parse_csv <- function(value) {
  if (is.null(value) || value == "") {
    return(NULL)
  }
  trimws(strsplit(value, ",")[[1]])
}

# Parse facet combinations (handle + for multiple facets)
parse_facets <- function(facets_str) {
  facet_specs <- parse_csv(facets_str)
  lapply(facet_specs, function(spec) {
    if (spec == "none" || spec == "None") {
      return(NULL)
    }
    # Split on + for multiple facets
    facets <- trimws(strsplit(spec, "\\+")[[1]])
    if (length(facets) == 1) facets[1] else facets
  })
}

# Load job configuration
load_job_config <- function() {
  if (!is.null(args$config)) {
    # Load from YAML file
    if (!file.exists(args$config)) {
      stop(sprintf("Config file not found: %s", args$config))
    }
    config <- yaml::read_yaml(args$config)
    
    # Process facets in YAML config to convert "none" to NULL
    for (i in seq_along(config$jobs)) {
      if (!is.null(config$jobs[[i]]$facets)) {
        # Convert each facet string using the same logic as command line args
        processed_facets <- lapply(config$jobs[[i]]$facets, function(spec) {
          if (spec == "none" || spec == "None") {
            return(NULL)
          }
          # Handle multi-facet combinations (e.g. "sex+age")  
          facets <- trimws(strsplit(as.character(spec), "\\+")[[1]])
          if (length(facets) == 1) facets[1] else facets
        })
        config$jobs[[i]]$facets <- processed_facets
      }
    }
    
    return(config$jobs)
  } else {
    # Build from command line arguments
    if (is.null(args$city)) {
      stop("Either --city or --config must be specified")
    }

    if (is.null(args$outcomes)) {
      stop("--outcomes must be specified when not using --config")
    }

    # Handle scenario vs scenarios
    scenarios <- NULL
    if (!is.null(args$scenario)) {
      scenarios <- c(args$scenario)
    } else if (!is.null(args$scenarios)) {
      scenarios <- parse_csv(args$scenarios)
    } else {
      stop("Either --scenario or --scenarios must be specified")
    }

    return(list(list(
      city = args$city,
      scenarios = scenarios,
      outcomes = parse_csv(args$outcomes),
      statistics = parse_csv(args$statistics),
      facets = parse_facets(args$facets)
    )))
  }
}

# Generate output file paths
generate_paths <- function(city, scenario, outcome, statistic, facet_spec, output_dir) {
  # Create directory structure
  city_dir <- file.path(output_dir, city)
  scenario_dir <- file.path(city_dir, scenario)

  if (!dir.exists(scenario_dir)) {
    dir.create(scenario_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Generate filename components
  if (is.null(facet_spec)) {
    facet_part <- "unfaceted"
  } else if (length(facet_spec) == 1) {
    facet_part <- paste0("facet_", facet_spec)
  } else {
    facet_part <- paste0("facet_", paste(facet_spec, collapse = "+"))
  }

  base_name <- paste0(outcome, "_", statistic, "_", facet_part)

  return(list(
    html = file.path(scenario_dir, paste0(base_name, ".html")),
    json = file.path(scenario_dir, paste0(base_name, ".json")),
    metadata = file.path(scenario_dir, paste0(base_name, "_metadata.json"))
  ))
}

# Check if plot already exists
plot_exists <- function(paths) {
  if (args$json_only || !args$include_html) {
    return(file.exists(paths$json))
  } else {
    return(file.exists(paths$json) && file.exists(paths$html))
  }
}

# Upload plot to S3
upload_to_s3 <- function(local_file, s3_key, bucket) {
  tryCatch(
    {
      # CONTAINER MODIFICATION: Use aws command (not awslocal)
      cmd <- sprintf('aws s3 cp "%s" "s3://%s/%s"', local_file, bucket, s3_key)

      # Execute command and capture both stdout and stderr
      result <- system(cmd, intern = FALSE, ignore.stdout = FALSE, ignore.stderr = FALSE)

      if (result == 0) {
        return(list(success = TRUE, s3_key = s3_key))
      } else {
        return(list(success = FALSE, error = sprintf("AWS CLI command failed with exit code: %d", result)))
      }
    },
    error = function(e) {
      return(list(success = FALSE, error = e$message))
    }
  )
}

# Register plot in DynamoDB via API
register_in_database <- function(city, scenario, outcome, statistic, facet_spec, s3_key, local_file, api_url) {
  tryCatch(
    {
      # Get file size
      file_size <- file.info(local_file)$size

      # Prepare registration data
      facet_choice <- if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+")

      registration_data <- list(
        city = city,
        scenario = scenario,
        outcome = outcome,
        statistic_type = statistic,
        facet_choice = facet_choice,
        s3_key = s3_key,
        file_size = file_size
      )

      # Convert to JSON
      json_data <- toJSON(registration_data, auto_unbox = TRUE)

      # Prepare curl command
      register_url <- paste0(api_url, "/plots/register")
      cmd <- sprintf(
        'curl -s -X POST "%s" -H "Content-Type: application/json" -d %s',
        register_url, shQuote(json_data)
      )

      # Execute curl
      result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)

      # Simple success check (should return 201 status in real implementation)
      return(list(success = TRUE, response = result))
    },
    error = function(e) {
      return(list(success = FALSE, error = e$message))
    }
  )
}

# Generate S3 key from plot metadata
generate_s3_key <- function(city, scenario, outcome, statistic, facet_spec) {
  facet_str <- if (is.null(facet_spec)) "unfaceted" else paste(facet_spec, collapse = "+")
  # Create descriptive S3 key: plots/C12580_cessation_incidence_mean.and.interval_sex.json
  key <- sprintf(
    "plots/%s_%s_%s_%s_%s.json",
    gsub("\\.", "", city), scenario, outcome, statistic, facet_str
  )
  return(key)
}

# Build API URL from gateway ID or use provided URL
get_api_url <- function() {
  if (!is.null(args$api_base_url)) {
    return(args$api_base_url)
  } else if (!is.null(args$api_gateway_id)) {
    # CONTAINER MODIFICATION: Use real AWS endpoints instead of LocalStack
    return(sprintf("https://%s.execute-api.us-east-1.amazonaws.com/prod", args$api_gateway_id))
  } else {
    return(NULL)
  }
}

# Generate single plot OR extract data frames (depending on output_mode)
generate_single_plot <- function(city, scenario, outcome, statistic, facet_spec,
                                 scenario_simset, baseline_simset, config, output_dir,
                                 output_mode = "plot") {
  tryCatch(
    {
      # Create settings object
      current_settings <- list(
        outcomes = outcome,
        facet.by = facet_spec,
        summary.type = statistic
      )

      # Create simulation ID
      current_sim_id <- list(
        settings = list(
          location = city,
          scenario = scenario
        ),
        simset = scenario_simset
      )

      # Mock store and baseline loading
      store <<- list(
        get_simulation = function(sim_id) list(status = "ready", settings = sim_id$settings, error_message = NULL),
        get_current_simulation_data = function(id) list(simset = sim_id$simset),
        get_original_base_simulation = function(id) NULL
      )
      sim_id <<- current_sim_id

      if (!is.null(baseline_simset)) {
        load_baseline_simulation <<- function(id, settings) baseline_simset
      }

      # === DATA OUTPUT MODE ===
      if (output_mode == "data") {
        return(generate_data_output(
          city, scenario, outcome, statistic, facet_spec,
          scenario_simset, baseline_simset, config, output_dir
        ))
      }

      # === PLOT OUTPUT MODE (existing behavior) ===
      # Prepare plot data
      plot_data <- prepare_plot_data(
        current_settings = current_settings,
        current_sim_id = current_sim_id,
        id = "prerun",
        scenario_options_config = config
      )

      if (isTRUE(plot_data$error)) {
        return(list(success = FALSE, error = plot_data$error_message))
      }

      # Render plot
      render_result <- render_plot(plot_data, current_settings)

      if (isTRUE(render_result$error)) {
        return(list(success = FALSE, error = render_result$error_message))
      }

      # Generate output paths
      paths <- generate_paths(city, scenario, outcome, statistic, facet_spec, output_dir)

      # Save HTML (only if include-html flag is set)
      if (args$include_html) {
        htmlwidgets::saveWidget(
          render_result$plotly_fig,
          file = paths$html,
          selfcontained = FALSE,
          libdir = "lib"
        )
      }

      # Save JSON
      plotly_json <- list(
        data = render_result$plotly_fig$x$data,
        layout = render_result$plotly_fig$x$layout
      )
      writeLines(toJSON(plotly_json, auto_unbox = TRUE, pretty = TRUE), paths$json)

      # Save metadata
      metadata <- list(
        city = city,
        scenario = scenario,
        outcome = outcome,
        statistic_type = statistic,
        facet_choice = if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+"),
        file_path = paths$html,
        json_path = paths$json,
        has_baseline = !is.null(baseline_simset),
        generation_time = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
      writeLines(toJSON(metadata, pretty = TRUE), paths$metadata)

      # Handle S3 upload if requested
      s3_result <- NULL
      if (args$upload_s3) {
        s3_key <- generate_s3_key(city, scenario, outcome, statistic, facet_spec)
        s3_result <- upload_to_s3(paths$json, s3_key, args$s3_bucket)

        if (!s3_result$success) {
          return(list(success = FALSE, error = paste("S3 upload failed:", s3_result$error)))
        }
      }

      # Handle database registration if requested
      db_result <- NULL
      if (args$register_db) {
        api_url <- get_api_url()
        if (is.null(api_url)) {
          return(list(success = FALSE, error = "Could not determine API URL for database registration"))
        }

        s3_key_for_db <- if (!is.null(s3_result)) s3_result$s3_key else generate_s3_key(city, scenario, outcome, statistic, facet_spec)
        db_result <- register_in_database(city, scenario, outcome, statistic, facet_spec, s3_key_for_db, paths$json, api_url)

        if (!db_result$success) {
          return(list(success = FALSE, error = paste("Database registration failed:", db_result$error)))
        }
      }

      return(list(
        success = TRUE,
        paths = paths,
        s3_result = s3_result,
        db_result = db_result
      ))
    },
    error = function(e) {
      return(list(success = FALSE, error = e$message))
    }
  )
}

# Generate data output (data frames instead of plots)
# Calls prepare_plot_local directly to get df.sim and df.truth
generate_data_output <- function(city, scenario, outcome, statistic, facet_spec,
                                 scenario_simset, baseline_simset, config, output_dir) {
  tryCatch(
    {
      # Build simset list with proper labels
      intervention_label <- "Intervention"
      if (!is.null(config) && !is.null(config[[scenario]])) {
        intervention_label <- config[[scenario]]$label %||% scenario
      } else {
        intervention_label <- scenario
      }

      sim_list <- list()
      if (!is.null(baseline_simset)) {
        sim_list[["Baseline"]] <- baseline_simset
      }
      sim_list[[intervention_label]] <- scenario_simset

      # Get data manager
      data_manager <- get.default.data.manager()

      # Call prepare_plot_local directly to get data frames
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

      # Convert data frames to JSON-friendly format
      sim_data <- NULL
      if (!is.null(prepared_data$df.sim) && nrow(prepared_data$df.sim) > 0) {
        # Select relevant columns and convert to list of records
        sim_cols <- c("year", "value", "simset", "outcome", "outcome.display.name")
        if ("value.lower" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "value.lower", "value.upper")
        # Include ALL facet.by columns (facet.by1, facet.by2, facet.by3, etc.) for multi-dimensional faceting
        facet_cols <- grep("^facet\\.by[0-9]+$", names(prepared_data$df.sim), value = TRUE)
        if (length(facet_cols) > 0) sim_cols <- c(sim_cols, facet_cols)
        if ("stratum" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "stratum")
        # Include sim column for individual.simulation statistic (identifies each simulation run)
        if ("sim" %in% names(prepared_data$df.sim)) sim_cols <- c(sim_cols, "sim")

        sim_cols <- intersect(sim_cols, names(prepared_data$df.sim))
        sim_data <- prepared_data$df.sim[, sim_cols, drop = FALSE]
      }

      obs_data <- NULL
      if (!is.null(prepared_data$df.truth) && nrow(prepared_data$df.truth) > 0) {
        # Select relevant columns
        obs_cols <- c("year", "value", "source", "outcome", "outcome.display.name")
        # Include ALL facet.by columns for multi-dimensional faceting
        facet_cols_obs <- grep("^facet\\.by[0-9]+$", names(prepared_data$df.truth), value = TRUE)
        if (length(facet_cols_obs) > 0) obs_cols <- c(obs_cols, facet_cols_obs)
        if ("data_url" %in% names(prepared_data$df.truth)) obs_cols <- c(obs_cols, "data_url")
        if ("stratum" %in% names(prepared_data$df.truth)) obs_cols <- c(obs_cols, "stratum")

        obs_cols <- intersect(obs_cols, names(prepared_data$df.truth))
        obs_data <- prepared_data$df.truth[, obs_cols, drop = FALSE]
      }

      # Build output structure
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

      # Add outcome metadata if available
      if (!is.null(prepared_data$details$outcome.metadata.list[[outcome]])) {
        output_data$metadata$outcome_metadata <- list(
          display_name = prepared_data$details$outcome.metadata.list[[outcome]]$display.name,
          units = prepared_data$details$outcome.metadata.list[[outcome]]$units,
          display_as_percent = prepared_data$details$outcome.metadata.list[[outcome]]$display.as.percent
        )
      }

      # Generate output path
      paths <- generate_paths(city, scenario, outcome, statistic, facet_spec, output_dir)

      # Write JSON
      writeLines(toJSON(output_data, auto_unbox = TRUE, pretty = TRUE, na = "null"), paths$json)

      return(list(
        success = TRUE,
        paths = paths,
        data = output_data
      ))
    },
    error = function(e) {
      return(list(success = FALSE, error = e$message))
    }
  )
}

# Main batch processing function
process_batch <- function() {
  start_time <- Sys.time()
  output_type <- if (args$output_mode == "data") "data extraction" else "plot generation"
  log_msg(sprintf("Starting batch %s", output_type))
  log_msg(sprintf("Output mode: %s", args$output_mode))
  log_msg(sprintf("Start time: %s", format(start_time, "%Y-%m-%d %H:%M:%S")))

  # Load configuration
  jobs <- load_job_config()
  log_msg(sprintf("Loaded %d job(s)", length(jobs)))

  # Validate S3/DB integration settings
  if (args$upload_s3) {
    log_msg("S3 upload enabled")
    log_msg(sprintf("S3 bucket: %s", args$s3_bucket))
  }

  if (args$register_db) {
    api_url <- get_api_url()
    if (is.null(api_url)) {
      stop("Database registration requested but could not determine API URL. Use --api-gateway-id or --api-base-url")
    }
    log_msg("Database registration enabled")
    log_msg(sprintf("API URL: %s", api_url))
  }

  # Calculate total plots for progress tracking
  total_plots <- 0
  for (job in jobs) {
    n_scenarios <- length(job$scenarios)
    n_outcomes <- length(job$outcomes)
    n_statistics <- length(job$statistics)
    n_facets <- length(job$facets)
    total_plots <- total_plots + (n_scenarios * n_outcomes * n_statistics * n_facets)
  }

  log_msg(sprintf("Total plots to generate: %d", total_plots))

  if (args$dry_run) {
    log_msg("DRY RUN - showing what would be generated:")
    plot_count <- 0
    for (job in jobs) {
      for (scenario in job$scenarios) {
        for (outcome in job$outcomes) {
          for (statistic in job$statistics) {
            for (facet_spec in job$facets) {
              plot_count <- plot_count + 1
              facet_str <- if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+")
              log_msg(sprintf(
                "[%d/%d] %s/%s: %s (%s, %s)",
                plot_count, total_plots, job$city, scenario, outcome, statistic, facet_str
              ))
            }
          }
        }
      }
    }
    return()
  }

  # Load global config once
  log_msg("Loading global configuration")
  scenario_options_config <- NULL
  tryCatch(
    {
      PRERUN_CONFIG <- get_page_complete_config("prerun")
      scenario_options_config <- PRERUN_CONFIG$selectors$scenario$options
    },
    error = function(e) {
      log_msg(sprintf("Warning: Could not load prerun config: %s", e$message), "WARN")
    }
  )

  # Process each job
  plot_count <- 0
  success_count <- 0
  error_count <- 0
  skipped_count <- 0

  for (job_idx in seq_along(jobs)) {
    job <- jobs[[job_idx]]
    log_msg(sprintf("Processing job %d/%d: City %s", job_idx, length(jobs), job$city))

    # Load baseline simulation once per city
    log_msg(sprintf("Loading baseline simulation for %s", job$city))
    baseline_simset <- load_baseline_direct(job$city, "prerun")

    # Process each scenario for this city
    for (scenario in job$scenarios) {
      log_msg(sprintf("Loading scenario simulation: %s/%s", job$city, scenario))

      # Load scenario simulation
      if (scenario == "base") {
        simset_file <- file.path("simulations/ryan-white/base", paste0(job$city, "_base.Rdata"))
      } else {
        simset_file <- file.path("simulations/ryan-white/prerun", job$city, paste0(scenario, ".Rdata"))
      }

      if (!file.exists(simset_file)) {
        log_msg(sprintf("ERROR: Simulation file not found: %s", simset_file), "ERROR")
        next
      }

      tryCatch(
        {
          loaded_data <- load(simset_file)
          scenario_simset <- get(loaded_data[1])
          log_msg(sprintf("Successfully loaded scenario simulation"))
        },
        error = function(e) {
          log_msg(sprintf("ERROR: Failed to load simulation: %s", e$message), "ERROR")
          next
        }
      )

      # Generate all outcome/statistic/facet combinations for this loaded simulation
      for (outcome in job$outcomes) {
        for (statistic in job$statistics) {
          for (facet_spec in job$facets) {
            plot_count <- plot_count + 1

            facet_str <- if (is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+")

            # Check if plot already exists
            paths <- generate_paths(job$city, scenario, outcome, statistic, facet_spec, args$output_dir)

            if (args$skip_existing && plot_exists(paths)) {
              log_msg(sprintf(
                "[%d/%d] SKIP: %s/%s/%s (%s, %s) - already exists",
                plot_count, total_plots, job$city, scenario, outcome, statistic, facet_str
              ))
              skipped_count <- skipped_count + 1
              next
            }

            log_msg(sprintf(
              "[%d/%d] GENERATING: %s/%s/%s (%s, %s)",
              plot_count, total_plots, job$city, scenario, outcome, statistic, facet_str
            ))

            # Generate the plot or data
            result <- generate_single_plot(
              job$city, scenario, outcome, statistic, facet_spec,
              scenario_simset, baseline_simset, scenario_options_config, args$output_dir,
              output_mode = args$output_mode
            )

            if (result$success) {
              success_count <- success_count + 1
              success_msg <- sprintf("SUCCESS: Generated %s", basename(result$paths$json))

              if (!is.null(result$s3_result)) {
                success_msg <- paste0(success_msg, sprintf(" | S3: %s", result$s3_result$s3_key))
              }

              if (!is.null(result$db_result)) {
                success_msg <- paste0(success_msg, " | DB: registered")
              }

              log_msg(success_msg)
            } else {
              error_count <- error_count + 1
              log_msg(sprintf("ERROR: %s", result$error), "ERROR")
            }
          }
        }
      }
    }
  }

  # Final summary
  end_time <- Sys.time()
  total_duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

  log_msg("Batch generation complete!")
  log_msg(sprintf("End time: %s", format(end_time, "%Y-%m-%d %H:%M:%S")))
  log_msg(sprintf("Total duration: %.1f seconds (%.2f minutes)", total_duration, total_duration / 60))
  log_msg(sprintf("Total plots processed: %d", plot_count))
  log_msg(sprintf("Successful: %d", success_count))
  log_msg(sprintf("Errors: %d", error_count))
  log_msg(sprintf("Skipped: %d", skipped_count))

  if (success_count > 0) {
    avg_time_per_plot <- total_duration / success_count
    log_msg(sprintf("Average time per successful plot: %.2f seconds", avg_time_per_plot))

    # Extrapolate to full scale
    estimated_64k_hours <- (64512 * avg_time_per_plot) / 3600
    log_msg(sprintf("Estimated time for 64K plots: %.1f hours", estimated_64k_hours))
  }

  if (error_count > 0) {
    quit(status = 1)
  }
}

# Run the batch processor
process_batch()
