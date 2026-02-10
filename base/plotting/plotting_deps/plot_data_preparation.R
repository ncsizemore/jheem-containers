# plot_data_preparation.R
# Extracted verbatim from plot_data_reactive in plot_panel.R

prepare_plot_data <- function(current_settings, current_sim_id, id, scenario_options_config = NULL) {
  # --- Load Full Page Config --- REMOVED - Use global PRERUN_CONFIG/CUSTOM_CONFIG ---
  # # Ensure get_page_complete_config is available
  # req(exists("get_page_complete_config") && is.function(get_page_complete_config))
  # page_config <- tryCatch(
  #   {
  #     get_page_complete_config(id) # Load config based on current page id
  #   },
  #   error = function(e) {
  #     warning(paste("Error loading page config for", id, ":", e$message))
  #     NULL
  #   }
  # )
  # req(page_config) # Stop if config loading failed

  # Initial UI state checks - these need to be outside the reactive
  # as they depend on input$ values directly related to visibility.
  # We'll check them inside the render functions instead.
  # req(input$visualization_state == "visible", cancelOutput = TRUE)
  # req(input$display_type == "plot", cancelOutput = TRUE)

  # Use the reactive values defined outside for this render execution
  # current_settings <- current_settings_reactive()
  # current_sim_id <- current_sim_id_reactive()

  # Validate settings and sim ID
  if (is.null(current_settings) || is.null(current_settings$outcomes)) {
    return(list(error = TRUE, error_message = "No settings or outcomes", error_type = "VALIDATION", sim_settings = NULL))
  }
  if (is.null(current_sim_id)) {
    return(list(error = TRUE, error_message = "No simulation ID", error_type = "VALIDATION", sim_settings = NULL))
  }

  # Get visualization config
  vis_config <- tryCatch(get_component_config("visualization"), error = function(e) {
    warning("Error loading visualization config: ", e$message)
    NULL
  })
  backend <- vis_config$plotting_backend %||% "ggplot"

  # Get current simulation and check for errors
  sim_state_check <- store$get_simulation(current_sim_id)
  if (is.null(sim_state_check) || sim_state_check$status == "error") {
    err_msg <- if (is.null(sim_state_check)) "No sim" else sim_state_check$error_message %||% "Sim error"
    return(list(error = TRUE, error_message = err_msg, error_type = "SIMULATION", sim_settings = NULL)) # Return NULL for sim_settings on error
  }

  # Get simulation data
  sim_state_data <- store$get_current_simulation_data(id)
  if (is.null(sim_state_data) || is.null(sim_state_data$simset)) {
    err_msg <- "No sim data."
    return(list(error = TRUE, error_message = err_msg, error_type = "PLOT", sim_settings = sim_state_check$settings)) # Return settings even on plot error
  }

  # Get baseline simulation if applicable
  sim_settings <- sim_state_check$settings
  if (is.null(sim_settings)) {
    return(list(error = TRUE, error_message = "No sim settings", error_type = "PLOT", sim_settings = NULL))
  }

  baseline_simset <- NULL
  if (id == "custom") {
    baseline_simset <- store$get_original_base_simulation(id)
  }
  if (is.null(baseline_simset)) {
    baseline_simset <- tryCatch(load_baseline_simulation(id, sim_settings), error = function(e) {
      warning("Error loading baseline simulation: ", e$message)
      NULL
    })
  }

  # --- Determine Data Manager ---
  data_manager_to_use <- NULL
  data_manager_path <- vis_config$data_manager_path # Read path from config
  if (!is.null(data_manager_path) && nzchar(data_manager_path) && file.exists(data_manager_path)) {
    tryCatch(
      {
        temp_env <- new.env(parent = emptyenv())
        loaded_names <- load(data_manager_path, envir = temp_env)
        if (length(loaded_names) == 1) {
          loaded_obj <- temp_env[[loaded_names[1]]]
          # Basic check if it looks like a data manager (adjust class name if needed)
          if (inherits(loaded_obj, "jheem.data.manager")) {
            data_manager_to_use <- loaded_obj
            # print(paste("Using data manager loaded from:", data_manager_path)) # Keep commented
          } else {
            warning(paste("Object loaded from", data_manager_path, "is not a jheem.data.manager object."))
          }
        } else {
          warning(paste("Expected one object in", data_manager_path, "but found", length(loaded_names)))
        }
      },
      error = function(e) {
        warning(paste("Error loading data manager from", data_manager_path, ":", e$message))
      }
    )
  }

  # Fallback to default if not loaded
  if (is.null(data_manager_to_use)) {
    # print("Using default data manager.") # Keep commented
    # Ensure get.default.data.manager() exists and is accessible
    if (exists("get.default.data.manager") && is.function(get.default.data.manager)) {
      data_manager_to_use <- get.default.data.manager()
    } else {
      warning("get.default.data.manager function not found. Cannot set data manager.")
      # Handle error appropriately - maybe return error state from reactive?
      return(list(error = TRUE, error_message = "Default data manager function not found.", error_type = "PLOT", sim_settings = sim_settings))
    }
  }
  # Ensure data_manager_to_use is not NULL before proceeding
  if (is.null(data_manager_to_use)) {
    return(list(error = TRUE, error_message = "Data manager is NULL", error_type = "PLOT", sim_settings = sim_settings))
  }

  # Set up plot arguments (common args)
  plot_args <- list(
    outcomes = current_settings$outcomes,
    facet.by = current_settings$facet.by,
    data.manager = data_manager_to_use, # Add the selected data manager
    summary.type = current_settings$summary.type
    # style.manager will be added conditionally later
  )

  # Prepare sim list or single simset
  sim_list_or_simset <- NULL
  if (!is.null(baseline_simset)) {
    # Determine Intervention Label Dynamically
    intervention_label <- "Intervention" # Default
    if (id == "prerun") {
      # For prerun page, use the scenario name from the loaded simulation's settings
      selected_scenario_value <- sim_state_check$settings$scenario # Get scenario ID from stored settings
      if (!is.null(selected_scenario_value) && nzchar(selected_scenario_value)) {
        # Find the display label using the passed scenario_options_config
        # scenario_options_config should be PRERUN_CONFIG$selectors$scenario$options
        if (!is.null(scenario_options_config)) {
          # Options are named lists: key=id, value=list(id=..., label=...)
          option_match <- scenario_options_config[[selected_scenario_value]]
          if (!is.null(option_match) && !is.null(option_match$label)) {
            intervention_label <- option_match$label
          } else {
            # Fallback if direct key lookup fails
            warning(paste("Could not find display label for scenario value:", selected_scenario_value))
            intervention_label <- selected_scenario_value # Fallback to value
          }
        } else {
          warning("Scenario options config was not passed to plot_panel_server.")
          intervention_label <- selected_scenario_value # Fallback
        }
      } else {
        warning("Scenario value not found in loaded simulation settings. Using default label.")
        # Keep default "Intervention" (already set above)
      }
    } else {
      # For other pages (e.g., custom), always use "Intervention"
      intervention_label <- "Intervention"
    }

    # Determine Baseline Label - Force to "Baseline"
    baseline_label <- "Baseline"

    # Create the list with determined labels
    sim_list <- list()
    sim_list[[baseline_label]] <- baseline_simset
    sim_list[[intervention_label]] <- sim_state_data$simset # Use determined label
    sim_list_or_simset <- sim_list
  } else {
    sim_list_or_simset <- list(sim_state_data$simset) # Pass as a list even if single
    # Adjust naming if needed, maybe use simset name or a default
    names(sim_list_or_simset) <- names(sim_list_or_simset) %||% "Simulation"
  }

  # Return prepared data
  list(
    error = FALSE,
    vis_config = vis_config,
    backend = backend,
    plot_args = plot_args,
    sim_list_or_simset = sim_list_or_simset,
    sim_settings = sim_settings # Pass sim_settings for title generation
    # sim_state_check and sim_state_data are implicitly used above
  )
}
