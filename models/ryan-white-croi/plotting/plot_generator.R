# plotting/plot_generator.R
# Plot generation logic adapted from batch_plot_generator.R
# Generates plots from simulation results in Lambda container environment

# Required libraries (already loaded in container)
# library(plotly)
# library(ggplot2)
# library(jsonlite)

# ============================================================================
# PLOT CONFIGURATION
# ============================================================================

#' Get key plot configurations for Ryan White simulations
#' @return List of plot configurations
get_key_plot_configurations <- function() {
  # Define key plots based on available Ryan White outcomes
  list(
    list(name = "diagnosed_prevalence_unfaceted", 
         outcome = "diagnosed.prevalence", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "diagnosed_prevalence_by_sex", 
         outcome = "diagnosed.prevalence", 
         statistic_type = "mean.and.interval", 
         facet_choice = "sex"),
    
    list(name = "adap_clients_unfaceted", 
         outcome = "adap.clients", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "non_adap_clients_unfaceted", 
         outcome = "non.adap.clients", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "oahs_clients_unfaceted", 
         outcome = "oahs.clients", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "adap_proportion_unfaceted", 
         outcome = "adap.proportion", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "oahs_suppression_unfaceted", 
         outcome = "oahs.suppression", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "adap_suppression_unfaceted", 
         outcome = "adap.suppression", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "rw_clients_unfaceted", 
         outcome = "rw.clients", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "new_diagnoses_unfaceted", 
         outcome = "new", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "prep_uptake_unfaceted", 
         outcome = "prep.uptake", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "awareness_unfaceted", 
         outcome = "awareness", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL),
    
    list(name = "testing_unfaceted", 
         outcome = "testing", 
         statistic_type = "mean.and.interval", 
         facet_choice = NULL)
  )
}

# ============================================================================
# MAIN PLOT GENERATION FUNCTION
# ============================================================================

#' Generate plots from simulation results
#' @param results Simulation results from run_custom_simulation (with intervention applied)
#' @param city City code (e.g., "C.12580")  
#' @param parameters Original parameters for context
#' @param baseline_simset The baseline simulation that the intervention was applied to
#' @return List of plots in Plotly JSON format
generate_simulation_plots <- function(results, city, parameters, baseline_simset) {
  
  cat("📊 Starting plot generation for", city, "...\n")
  
  # Validate we have both baseline and intervention results
  if (is.null(baseline_simset)) {
    stop("Baseline simulation is required for plot generation")
  }
  
  cat("  ✅ Generating comparison plots (baseline vs intervention)\n")
  
  # Get plot configurations
  plot_configs <- get_key_plot_configurations()
  
  # Get scenario label for the intervention
  scenario_label <- paste0(
    "RW Loss ", parameters$adap_suppression_loss, "/",
    parameters$oahs_suppression_loss, "/", 
    parameters$other_suppression_loss, "%"
  )
  
  # Initialize plots list
  plots <- list()
  
  # Generate each configured plot
  for (config in plot_configs) {
    cat("  Generating plot:", config$name, "...\n")
    
    tryCatch({
      # Generate single plot using adapted batch logic
      plot_json <- generate_single_plot_json(
        city = city,
        scenario = "custom",  # Custom simulation
        scenario_label = scenario_label,
        outcome = config$outcome,
        statistic_type = config$statistic_type,
        facet_spec = config$facet_choice,
        scenario_simset = results,
        baseline_simset = baseline_simset
      )
      
      # Store plot JSON
      plots[[config$name]] <- plot_json
      cat("    ✅ Successfully generated", config$name, "\n")
      
    }, error = function(e) {
      cat("    ❌ Failed to generate", config$name, ":", e$message, "\n")
      
      # Store error placeholder
      plots[[config$name]] <- list(
        error = TRUE,
        message = e$message,
        config = config
      )
    })
  }
  
  cat("✅ Plot generation complete. Generated", 
      sum(!sapply(plots, function(p) isTRUE(p$error))), 
      "of", length(plots), "plots successfully\n")
  
  return(plots)
}

# ============================================================================
# SINGLE PLOT GENERATION (ADAPTED FROM BATCH)
# ============================================================================

#' Generate a single plot as JSON (adapted from batch_plot_generator.R)
#' @param city City code
#' @param scenario Scenario identifier
#' @param scenario_label Display label for scenario
#' @param outcome Outcome to plot
#' @param statistic_type Statistic type (e.g., "mean.and.interval")
#' @param facet_spec Facet specification (NULL or character vector)
#' @param scenario_simset Simulation results (with intervention applied)
#' @param baseline_simset Baseline simulation (before intervention)
#' @return Plotly JSON object
generate_single_plot_json <- function(city, scenario, scenario_label, outcome, 
                                     statistic_type, facet_spec, 
                                     scenario_simset, baseline_simset) {
  
  # Create settings object (mimics Shiny app control_manager)
  current_settings <- list(
    outcomes = outcome,
    facet.by = facet_spec,
    summary.type = statistic_type
  )
  
  # Create simulation ID object
  current_sim_id <- list(
    settings = list(
      location = city,
      scenario = scenario
    ),
    simset = scenario_simset
  )
  
  # Create mock store (required by plot_data_preparation.R)
  store <- list(
    get_simulation = function(sim_id) {
      list(
        status = "ready", 
        settings = sim_id$settings, 
        error_message = NULL
      )
    },
    get_current_simulation_data = function(id) {
      list(simset = current_sim_id$simset)
    },
    get_original_base_simulation = function(id) {
      NULL  # We'll handle baseline separately
    }
  )
  
  # Make store available globally (required by plotting functions)
  assign("store", store, envir = .GlobalEnv)
  assign("sim_id", current_sim_id, envir = .GlobalEnv)
  
  # Set up baseline loading function if baseline provided
  if (!is.null(baseline_simset)) {
    load_baseline_simulation <- function(id, settings) {
      return(baseline_simset)
    }
    assign("load_baseline_simulation", load_baseline_simulation, envir = .GlobalEnv)
  }
  
  # Get scenario configuration for proper labeling
  scenario_options_config <- list()
  scenario_options_config[[scenario]] <- list(
    id = scenario,
    label = scenario_label
  )
  
  # Prepare plot data using existing logic
  plot_data <- prepare_plot_data(
    current_settings = current_settings,
    current_sim_id = current_sim_id,
    id = "custom",  # Use custom mode
    scenario_options_config = scenario_options_config
  )
  
  # Check for data preparation errors
  if (isTRUE(plot_data$error)) {
    stop(paste("Data preparation failed:", plot_data$error_message))
  }
  
  # Render plot using existing logic
  render_result <- render_plot(plot_data, current_settings)
  
  # Check for rendering errors
  if (isTRUE(render_result$error)) {
    stop(paste("Plot rendering failed:", render_result$error_message))
  }
  
  # Extract Plotly JSON from rendered result
  plotly_fig <- render_result$plotly_fig
  
  # Convert to JSON format expected by API
  plotly_json <- list(
    data = plotly_fig$x$data,
    layout = plotly_fig$x$layout,
    config = list(
      displayModeBar = FALSE,  # Hide toolbar for cleaner display
      responsive = TRUE
    )
  )
  
  # Add metadata
  plotly_json$metadata <- list(
    city = city,
    scenario = scenario,
    outcome = outcome,
    statistic_type = statistic_type,
    facet_choice = if(is.null(facet_spec)) "none" else paste(facet_spec, collapse = "+"),
    has_baseline = !is.null(baseline_simset),
    generation_time = Sys.time()
  )
  
  return(plotly_json)
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

#' Create a mock plot for testing when real plotting fails
#' @param outcome Outcome name
#' @param error_message Error message to display
#' @return Mock plotly JSON structure
create_mock_plot <- function(outcome, error_message = NULL) {
  # Create simple line plot showing intervention effect
  years <- 2020:2035
  baseline_values <- 100 + rnorm(length(years), 0, 5)
  intervention_values <- baseline_values * seq(1, 0.7, length.out = length(years))
  
  plotly_json <- list(
    data = list(
      list(
        x = years,
        y = baseline_values,
        type = "scatter",
        mode = "lines+markers",
        name = "Baseline",
        line = list(color = "blue", dash = "dash")
      ),
      list(
        x = years,
        y = intervention_values,
        type = "scatter", 
        mode = "lines+markers",
        name = "Intervention",
        line = list(color = "red")
      )
    ),
    layout = list(
      title = paste(outcome, "- Mock Data"),
      xaxis = list(title = "Year"),
      yaxis = list(title = outcome),
      showlegend = TRUE,
      annotations = if(!is.null(error_message)) list(
        list(
          text = paste("Error:", error_message),
          x = 0.5,
          y = 0.5,
          xref = "paper",
          yref = "paper",
          showarrow = FALSE,
          font = list(color = "red")
        )
      ) else list()
    )
  )
  
  return(plotly_json)
}

#' Validate that required plotting functions are available
#' @return TRUE if all required functions exist
validate_plotting_dependencies <- function() {
  required_functions <- c(
    "prepare_plot_data",
    "render_plot", 
    "simplot_local",
    "create_style_manager_from_config",
    "customize_plot_from_config"
  )
  
  missing_functions <- c()
  for (fn in required_functions) {
    if (!exists(fn, mode = "function")) {
      missing_functions <- c(missing_functions, fn)
    }
  }
  
  if (length(missing_functions) > 0) {
    cat("❌ Missing required plotting functions:", 
        paste(missing_functions, collapse = ", "), "\n")
    cat("   Make sure all plotting dependencies are sourced\n")
    return(FALSE)
  }
  
  cat("✅ All plotting dependencies validated\n")
  return(TRUE)
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Validate dependencies on load
if (!validate_plotting_dependencies()) {
  warning("Plot generator loaded but some dependencies are missing. ",
          "Real plots may fail - mock plots will be used as fallback.")
}

cat("📦 Plot generator module loaded (BATCH-ADAPTED implementation)\n")
