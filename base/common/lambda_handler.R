# lambda_handler.R
# Clean entry point for JHEEM Ryan White Lambda container
# Loads workspace and coordinates simulation pipeline

cat("🚀 JHEEM Ryan White Lambda handler starting...\n")

# Load the pre-built workspace (contains RW.SPECIFICATION, data managers, etc.)
cat("📦 Loading Ryan White workspace...\n")
system.time({
  load("ryan_white_workspace.RData")
  
  # Export internal jheem2 functions (needed for specifications)
  pkg_env <- asNamespace("jheem2")
  internal_fns <- ls(pkg_env, all.names = TRUE)
  for (fn in internal_fns) {
    if (exists(fn, pkg_env, inherits = FALSE) && is.function(get(fn, pkg_env))) {
      assign(fn, get(fn, pkg_env), envir = .GlobalEnv)
    }
  }
})

cat("✅ Workspace loaded with", length(ls()), "objects\n")
cat("✅ RW.SPECIFICATION available:", exists("RW.SPECIFICATION"), "\n")

# Load required packages for simulation execution
library(distributions)  # For generate.random.samples function
library(locations)       # For get.location.name function
cat("✅ Required packages loaded\n")

# Restore VERSION.MANAGER state from hidden object
cat("🔧 Restoring 'rw' model version from saved state...\n")

if (!exists(".jheem2_state", envir = .GlobalEnv)) {
  stop("FATAL: .jheem2_state not found in workspace - VERSION.MANAGER state missing")
}

jheem2_ns <- asNamespace("jheem2")
vm <- jheem2_ns$VERSION.MANAGER

# Clear current VERSION.MANAGER state
rm(list = ls(vm, all.names = TRUE), envir = vm)

# Restore from saved state
saved_state <- .jheem2_state$version_manager
for (name in names(saved_state)) {
  vm[[name]] <- saved_state[[name]]
}

cat("✅ Restored", length(saved_state), "VERSION.MANAGER elements\n")

# Restore ONTOLOGY.MAPPING.MANAGER using consistent approach
cat("🔧 Restoring ONTOLOGY.MAPPING.MANAGER...\n")
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = jheem2_ns)
ont_state <- .jheem2_state$ontology_mapping_manager
for (name in names(ont_state)) {
  assign(name, ont_state[[name]], envir = ont_mgr)
}
cat("✅ Restored", length(ont_state), "ONTOLOGY.MAPPING.MANAGER elements\n")

# Verify restoration
if (!("versions" %in% ls(vm, all.names = TRUE) && "rw" %in% vm$versions)) {
  stop("FATAL: 'rw' version not found after VERSION.MANAGER restoration")
}

cat("✅ 'rw' version successfully restored\n")

# Load plotting utilities
source("plotting_minimal.R")

# Load plotting dependencies (using same pattern as batch_plot_generator.R)
tryCatch(
  {
    source("plotting/plotting_deps/simplot_local_mods.R")
    source("plotting/plotting_deps/plotting_local.R")
    source("plotting/plotting_deps/load_config.R")
    source("plotting/plotting_deps/plot_panel.R")
    source("plotting/plotting_deps/plot_data_preparation.R")
    source("plotting/plotting_deps/plot_rendering.R")
    source("plotting/plotting_deps/baseline_loading.R")
    cat("✅ Plotting dependencies loaded\n")
  },
  error = function(e) {
    cat("❌ Error loading plotting dependencies:", e$message, "\n")
    # Continue anyway - plotting might still work with minimal dependencies
  }
)

# Set up data manager function (same as batch_plot_generator.R)
get.default.data.manager <- function() {
  # Container prioritizes WEB.DATA.MANAGER for real-world data points
  # but keeps RW.DATA.MANAGER as fallback for compatibility
  if (exists("WEB.DATA.MANAGER", envir = .GlobalEnv)) {
    cat("  📡 Using WEB.DATA.MANAGER (with real-world data points)\n")
    return(WEB.DATA.MANAGER)
  } else if (exists("RW.DATA.MANAGER", envir = .GlobalEnv)) {
    cat("  🧪 Using RW.DATA.MANAGER (fallback - may not have real-world data overlay)\n")
    return(RW.DATA.MANAGER)
  } else {
    warning("No data manager found in workspace (checked WEB.DATA.MANAGER, RW.DATA.MANAGER)")
    return(NULL)
  }
}

# Load simplified simulation pipeline
source("simulation/simple_ryan_white.R")
source("plotting/plot_generator.R")

# Load test module
source("tests/test_simulation.R")

# ============================================================================
# LAMBDA HANDLER FUNCTION
# ============================================================================

#' Main Lambda handler function
#' @param event Lambda event object with city, base_simulation_path, parameters
#' @param context Lambda context object
#' @return JSON response with results or error
handle_simulation_request <- function(event, context) {
  cat("📥 Received simulation request\n")
  
  tryCatch({
    # Parse request parameters
    city <- event$city %||% "C.12580"
    base_simulation_path <- event$base_simulation_path %||% "/tmp/base_simulation.rdata"
    parameters <- event$parameters %||% list(
      adap_suppression_loss = 30,
      oahs_suppression_loss = 25,
      other_suppression_loss = 40
    )
    
    cat("🏙️ Processing simulation for city:", city, "\n")
    cat("📁 Base simulation path:", base_simulation_path, "\n")
    
    # Check that base simulation file exists
    if (!file.exists(base_simulation_path)) {
      stop("Base simulation file not found: ", base_simulation_path)
    }
    
    # Step 1: Load base simulation (already downloaded by trigger lambda)
    cat("📦 Loading base simulation data...\n")
    
    # Load the .rdata file and get the simulation object
    loaded_objects <- load(base_simulation_path)
    cat("  Loaded objects:", paste(loaded_objects, collapse = ", "), "\n")
    
    # Get the first loaded object (should be the simulation set)
    base_simset <- get(loaded_objects[1])
    cat("✅ Base simulation loaded with class:", class(base_simset), "\n")
    
    # Validate parameters
    validate_intervention_parameters(parameters)
    
    # Step 2: Create Ryan White intervention
    cat("🔧 Creating Ryan White intervention...\n")
    intervention <- create_ryan_white_intervention(parameters)
    
    # Step 3: Run simulation  
    cat("🚀 Running custom simulation...\n")
    results <- run_custom_simulation(base_simset, intervention)
    
    # Step 4: Generate plots
    cat("📊 Generating plots...\n")
    # Note: base_simset is the baseline simulation that the intervention was applied to
    # We pass it for comparison plots showing baseline vs intervention
    plots <- generate_simulation_plots(results, city, parameters, base_simset)
    
    # Return success response
    response <- list(
      statusCode = 200,
      body = list(
        message = "Ryan White simulation completed successfully",
        city = city,
        parameters = parameters,
        plots = plots,
        metadata = list(
          workspace_objects = length(ls()),
          specification_available = exists("RW.SPECIFICATION"),
          timestamp = Sys.time()
        )
      )
    )
    
    return(toJSON(response, auto_unbox = TRUE, pretty = TRUE))
    
  }, error = function(e) {
    cat("❌ Handler error:", e$message, "\n")
    
    error_response <- list(
      statusCode = 500,
      body = list(
        error = paste("Simulation error:", e$message),
        timestamp = Sys.time()
      )
    )
    return(toJSON(error_response, auto_unbox = TRUE))
  })
}

# ============================================================================
# TESTING (when not in Lambda environment)
# ============================================================================
if (interactive() || !exists("lambda_runtime")) {
  cat("🧪 Testing handler locally...\n")
  
  test_event <- list(
    city = "C.12580",
    base_simulation_path = "/app/test_base_sim.rdata",
    parameters = list(
      adap_suppression_loss = 50,
      oahs_suppression_loss = 30,
      other_suppression_loss = 40
    )
  )
  
  result <- handle_simulation_request(test_event, NULL)
  cat("📤 Handler result:\n")
  cat(substr(result, 1, 500), "...\n")  # Show first 500 chars
}

cat("✅ Ryan White Lambda handler ready\n")
