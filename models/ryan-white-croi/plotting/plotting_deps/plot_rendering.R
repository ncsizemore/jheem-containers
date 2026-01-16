# plot_rendering.R
# Extracted verbatim from ggplotly rendering logic in plot_panel.R (lines ~585-765)

render_plot <- function(plot_data, current_settings) {
  # Check for initial errors from reactive
  if (isTRUE(plot_data$error)) {
    return(list(error = TRUE, error_message = plot_data$error_message, error_type = plot_data$error_type))
  }

  # Check if backend is ggplotly
  if (plot_data$backend != "ggplotly") {
    return(list(error = TRUE, error_message = paste("Backend is", plot_data$backend, "but expected ggplotly"), error_type = "PLOT"))
  }

  # Generate the plot
  generated_ggplotly_plot <- tryCatch(
    {
      # Ensure required functions exist
      if (!exists("create_style_manager_from_config") || !is.function(create_style_manager_from_config)) {
        stop("create_style_manager_from_config function not found")
      }
      if (!exists("customize_plot_from_config") || !is.function(customize_plot_from_config)) {
        stop("customize_plot_from_config function not found")
      }
      if (!exists("simplot_local") || !is.function(simplot_local)) {
        stop("simplot_local function not found")
      }

      # Get plot args from reactive data
      plot_args_final <- plot_data$plot_args
      plot_args_final$append.url <- TRUE # Enable append.url (fix is now in simplot_local_mods.R)
      # Explicitly set title to NULL to prevent simplot from adding one # REMOVED THIS LINE
      # print("[PLOT PANEL - ggplotly] Setting title = NULL in simplot args.") # REMOVED THIS LINE

      # Add style manager for ggplot, passing simplify_legend flag
      # simplify_flag <- length(plot_data$sim_list_or_simset) == 2 # simplify_legend not used currently
      style_manager <- create_style_manager_from_config(plot_data$vis_config) # simplify_legend = simplify_flag)
      if (!is.null(style_manager)) {
        plot_args_final$style.manager <- style_manager
      }

      # NEW: Create and add the custom facet labeller
      custom_labeller <- create_custom_facet_labeller(
        label_mappings = plot_data$vis_config$facet_labels,
        original_facet_vars = plot_data$plot_args$facet.by
      )
      if (!is.null(custom_labeller)) {
        plot_args_final$facet_labeller <- custom_labeller
      }

      # Call LOCAL simplot to get ggplot object
      the_ggplot <- do.call(simplot_local, c(plot_data$sim_list_or_simset, plot_args_final))
      if (is.null(the_ggplot)) {
        stop("simplot_local returned NULL")
      }

      # Force remove title potentially added by simplot (handled by UI now)
      the_ggplot <- the_ggplot + theme(plot.title = element_blank()) # RE-ADD THIS LINE

      # Calculate number of lines needed for facet labels
      num_facet_lines <- 1 # Start with 1 for the outcome name
      if (!is.null(plot_data$plot_args$facet.by)) {
        num_facet_lines <- num_facet_lines + length(plot_data$plot_args$facet.by)
      }
      # print(paste("[PLOT PANEL - ggplotly] Calculated num_facet_lines:", num_facet_lines)) # Keep commented

      # Apply ggplot customizations, passing the number of lines
      the_ggplot <- customize_plot_from_config(the_ggplot, plot_data$vis_config, num_facet_lines = num_facet_lines)
      if (is.null(the_ggplot)) {
        stop("customize_plot_from_config returned NULL")
      }

      # Add debugging for ribbon investigation
      has_ribbon_geom <- FALSE
      ribbon_data_list <- list()
      ribbon_layers <- c()

      # Check if the plot contains ribbon geoms
      if (length(the_ggplot$layers) > 0) {
        for (i in 1:length(the_ggplot$layers)) {
          if (inherits(the_ggplot$layers[[i]]$geom, "GeomRibbon")) {
            has_ribbon_geom <- TRUE
            # print(paste("Found GeomRibbon in layer", i)) # Keep commented

            # Try to extract ribbon data
            ribbon_data <- suppressWarnings(ggplot2::layer_data(the_ggplot, i))
            # print("Ribbon columns:") # Keep commented
            # print(names(ribbon_data)) # Keep commented
            # print("First few rows:") # Keep commented
            # print(head(ribbon_data)) # Keep commented

            # Store ribbon data for later use
            ribbon_data_list[[length(ribbon_data_list) + 1]] <- ribbon_data
            ribbon_layers <- c(ribbon_layers, i)
          }
        }

        if (!has_ribbon_geom) {
          # print("No GeomRibbon found in plot layers") # Keep commented
          # print("Layer classes:") # Keep commented
          # print(sapply(the_ggplot$layers, function(x) class(x$geom)[1])) # Keep commented
        }
      }

      # Force 2-column layout by explicitly modifying the facet
      if (inherits(the_ggplot$facet, "FacetWrap")) {
        # Directly modify the facet parameters to use 2 columns
        the_ggplot$facet$params$ncol <- 2

        # Calculate rows based on number of panels
        facet_layout <- ggplot2::ggplot_build(the_ggplot)$layout$layout
        n_facets <- nrow(facet_layout)
        n_rows <- ceiling(n_facets / 2)

        # Set calculated height based on number of rows
        pixels_per_row <- 250 # Estimated height per row
        buffer_pixels <- 250 # Increased extra space for title, legend, etc.
        calculated_height <- (n_rows * pixels_per_row) + buffer_pixels
      } else {
        # Default height if no facets
        calculated_height <- 600
      }

      # --- REMOVED Manual Ribbon Recreation Loop ---
      # This is no longer needed as execute_simplot_local now uses standard geom_ribbon.

      # Explicitly NULLify the title label before ggplotly conversion
      # print("[PLOT PANEL - ggplotly] Setting plot$labels$title to NULL before ggplotly()") # Keep commented
      the_ggplot$labels$title <- NULL

      # Convert to plotly with explicit height
      plotly_fig <- plotly::ggplotly(the_ggplot,
        height = calculated_height,
        tooltip = "text" # Use the 'text' aesthetic from simplot_local
      )

      # Apply Plotly workarounds using helper functions
      plotly_fig <- simplify_plotly_legend(plotly_fig, names(plot_data$sim_list_or_simset))
      plotly_fig <- adjust_plotly_facet_labels(plotly_fig, adjustment_offset = 0.01)

      # GGPLOTLY OVERRIDE: Manually position legend at the top for ggplotly backend,
      # overriding the theme setting from visualization.yaml which may not translate correctly.
      # Position legend at the top, horizontally
      plotly_fig <- plotly_fig %>% layout(legend = list(
        orientation = "h", # Horizontal layout
        yanchor = "bottom", # Anchor legend bottom to y position
        y = 1.02, # Position slightly above plot area (adjust as needed)
        xanchor = "center", # Anchor legend center to x position
        x = 0.5 # Center horizontally
      ))

      plotly_fig
    },
    error = function(e) {
      err_msg <- conditionMessage(e)
      return(list(error = TRUE, error_message = err_msg, error_type = "PLOT"))
    }
  ) # end tryCatch

  # Check if we got an error from tryCatch
  if (is.list(generated_ggplotly_plot) && isTRUE(generated_ggplotly_plot$error)) {
    return(generated_ggplotly_plot)
  }

  return(list(error = FALSE, plotly_fig = generated_ggplotly_plot))
}
