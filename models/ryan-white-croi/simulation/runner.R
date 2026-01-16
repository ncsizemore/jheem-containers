# simulation/runner.R
# Simulation execution logic using JHEEM2 SimulationRunner

# ============================================================================
# SIMULATION RUNNER CLASS (from jheem2_interactive)
# ============================================================================

#' Run simulations with interventions
#' @param provider SimulationProvider instance for data access
#' @export
SimulationRunner <- R6::R6Class(
  "SimulationRunner",
  public = list(
    provider = NULL,
    initialize = function(provider) {
      self$provider <- provider
    },
    
    #' Load a simulation set
    #' @param simset_key String identifying the simset
    #' @return JHEEM2 simulation set
    load_simset = function(simset_key) {
      self$provider$load_simset(simset_key)
    },
    
    #' Run a single intervention
    #' @param intervention JHEEM2 intervention object
    #' @param simset JHEEM2 simulation set
    #' @param start_year Optional start year for simulation
    #' @param end_year Optional end year for simulation
    #' @param verbose Whether to print verbose output
    #' @param progress_callback Optional function to report progress
    run_intervention = function(intervention, simset,
                               start_year = NULL,
                               end_year = NULL,
                               verbose = TRUE,
                               progress_callback = NULL) {
      # Validate inputs
      if (is.null(intervention)) stop("Intervention cannot be null")
      if (is.null(simset)) stop("Simulation set cannot be null")
      
      # Copy simset to avoid modifying original
      simset <- copy.simulation.set(simset)
      
      # Check if this is a NULL intervention
      if (is(intervention, "null.intervention")) {
        if (verbose) {
          cat("Using null intervention - returning original simset\n")
        }
        return(simset)
      }
      
      # Basic validation of intervention structure
      if (verbose) {
        cat("Running intervention:", intervention$code, "\n")
        if (!is.null(intervention$effects)) {
          cat("Intervention has", length(intervention$effects), "effects\n")
        } else if (!is.null(intervention$foregrounds)) {
          cat("Intervention has", length(intervention$foregrounds), "foregrounds\n")
        }
      }
      
      # Run intervention
      tryCatch({
        if (is.function(intervention$run)) {
          # Create listener function that wraps our progress_callback if provided
          listener <- NULL
          if (!is.null(progress_callback)) {
            listener <- function(index, total, done) {
              # Call the progress callback with current state
              progress_callback(index, total, done)
            }
          }
          
          # Run the intervention with the listener
          intervention$run(simset,
                          start.year = start_year,
                          end.year = end_year,
                          verbose = verbose,
                          listener = listener)
        } else {
          stop("Intervention does not have a run method")
        }
      }, error = function(e) {
        stop(sprintf("Error running intervention: %s", e$message))
      })
    }
  )
)

# ============================================================================
# SIMULATION EXECUTION FUNCTIONS
# ============================================================================

#' Run custom simulation with Ryan White intervention
#' @param base_simset Base simulation set (loaded from S3)
#' @param intervention Ryan White intervention object
#' @param start_year Start year for simulation (default 2020)
#' @param end_year End year for simulation (default 2035)
#' @param verbose Whether to print verbose output (default TRUE)
#' @return Simulation results
run_custom_simulation <- function(base_simset, intervention, 
                                start_year = 2020, end_year = 2035, verbose = TRUE) {
  
  cat("🚀 Running custom simulation...\n")
  cat("  Base simset class:", class(base_simset), "\n")
  cat("  Intervention code:", intervention$code, "\n")
  cat("  Years:", start_year, "to", end_year, "\n")
  
  # Validate inputs first
  validate_simulation_inputs(base_simset, intervention)
  
  tryCatch({
    # Create SimulationRunner instance (no provider needed for intervention-only runs)
    cat("  Creating SimulationRunner instance...\n")
    runner <- SimulationRunner$new(provider = NULL)
    
    # Create progress callback for monitoring
    progress_callback <- function(index, total, done) {
      if (verbose) {
        # Handle inconsistent total reporting from JHEEM2
        # Track max total and avoid duplicate reporting
        if (!exists("progress_state", envir = environment(progress_callback))) {
          assign("progress_state", list(max_total = total, last_index = -1), 
                envir = environment(progress_callback))
        }
        
        state <- get("progress_state", envir = environment(progress_callback))
        
        # Update max total if we see a larger one
        if (total > state$max_total) {
          state$max_total <- total
          assign("progress_state", state, envir = environment(progress_callback))
        }
        
        # Only print if index actually advanced and we have meaningful total
        if (index > state$last_index && state$max_total > 1) {
          percent <- round((index / state$max_total) * 100)
          
          # Use carriage return for single-line updates
          cat(sprintf("\r    Progress: %d/%d (%d%%) %s", 
                     index, state$max_total, percent,
                     if(index == state$max_total) "- Complete!" else ""))
          
          # Update state
          state$last_index <- index
          assign("progress_state", state, envir = environment(progress_callback))
          
          # Add newline only when complete
          if (index == state$max_total) {
            cat("\n")
          }
        }
      }
    }
    
    # Copy simset to avoid modifying original (following Shiny app pattern)
    cat("  Copying base simulation set...\n")
    working_simset <- copy.simulation.set(base_simset)
    
    # Run intervention on simset (this is where the actual simulation happens)
    cat("  Running intervention on simulation set...\n")
    cat("  This may take several minutes...\n")
    
    start_time <- Sys.time()
    
    results <- runner$run_intervention(
      intervention = intervention,
      simset = working_simset,
      start_year = start_year,
      end_year = end_year,
      verbose = verbose,
      progress_callback = progress_callback
    )
    
    end_time <- Sys.time()
    duration <- as.numeric(difftime(end_time, start_time, units = "mins"))
    
    cat("✅ Simulation completed successfully!\n")
    cat("   Duration:", round(duration, 2), "minutes\n")
    cat("   Result class:", class(results), "\n")
    
    return(results)
    
  }, error = function(e) {
    cat("❌ Simulation error:", e$message, "\n")
    
    # Try to provide more context about the error
    if (grepl("intervention", tolower(e$message))) {
      cat("   This may be an intervention-related error.\n")
      cat("   Check that the intervention was created correctly.\n")
    } else if (grepl("simset", tolower(e$message))) {
      cat("   This may be a simulation set error.\n") 
      cat("   Check that the base simulation loaded correctly.\n")
    }
    
    stop("Simulation failed: ", e$message)
  })
}

#' Validate simulation inputs
#' @param base_simset Base simulation set
#' @param intervention Intervention object  
#' @return TRUE if valid, stops with error if invalid
validate_simulation_inputs <- function(base_simset, intervention) {
  cat("  Validating simulation inputs...\n")
  
  # Check base simset
  if (is.null(base_simset)) {
    stop("Base simulation set cannot be null")
  }
  
  cat("    Simset class:", class(base_simset), "\n")
  
  # Check intervention
  if (is.null(intervention)) {
    stop("Intervention cannot be null")
  }
  
  if (is.null(intervention$code)) {
    stop("Intervention must have a code")
  }
  
  # Check if it's a null intervention (special case)
  if (is(intervention, "null.intervention")) {
    cat("    Using null intervention (no effects will be applied)\n")
  } else {
    # Check for effects or run method
    has_effects <- !is.null(intervention$effects) && length(intervention$effects) > 0
    has_run_method <- !is.null(intervention$run) && is.function(intervention$run)
    
    if (!has_effects && !has_run_method) {
      stop("Intervention must have either effects or a run method")
    }
    
    cat("    Intervention has", 
        if (has_effects) paste(length(intervention$effects), "effects") else "no effects",
        "and",
        if (has_run_method) "a run method" else "no run method", "\n")
  }
  
  cat("  ✅ Simulation inputs validated\n")
  return(TRUE)
}

#' Get simulation metadata from results
#' @param results Simulation results
#' @return List of metadata
get_simulation_metadata <- function(results) {
  metadata <- list(
    class = class(results),
    completed_at = Sys.time()
  )
  
  # Try to extract additional metadata if available
  tryCatch({
    if (!is.null(results$metadata)) {
      metadata$jheem_metadata <- results$metadata
    }
    
    if (!is.null(names(results))) {
      metadata$result_names <- names(results)
    }
    
    if (is.list(results)) {
      metadata$result_length <- length(results)
    }
    
  }, error = function(e) {
    cat("Warning: Could not extract simulation metadata:", e$message, "\n")
  })
  
  return(metadata)
}

cat("📦 Simulation runner module loaded (REAL implementation)\n")
