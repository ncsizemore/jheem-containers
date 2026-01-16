# src/ui/components/common/display/plot_customizer.R

#' Customize a ggplot object from configuration
#' @param plot The ggplot object to customize
#' @param config The visualization configuration containing customization settings
#' @param num_facet_lines (Optional) The number of lines expected in the facet strip label
#' @return The modified ggplot object
customize_plot_from_config <- function(plot, config, num_facet_lines = 1) { # Add num_facet_lines argument
  # Debug print to see if function is being called
  # print("[PLOT_CUSTOMIZER] customize_plot_from_config() called")
  # print(paste("[PLOT_CUSTOMIZER] Received num_facet_lines:", num_facet_lines))

  # If no config provided or no customizations defined, return original plot
  if (is.null(config)) {
    # print("[PLOT_CUSTOMIZER] config is NULL, returning original plot")
    return(plot)
  }

  # Debug print for config structure
  # print("[PLOT_CUSTOMIZER] config structure:")
  # print(str(config))

  if (is.null(config$plot_customizations)) {
    # print("[PLOT_CUSTOMIZER] plot_customizations section is NULL, returning original plot")
    return(plot)
  }

  customizations <- config$plot_customizations

  # Debug print for customizations
  # print("[PLOT_CUSTOMIZER] Customizations to apply:")
  # print(str(customizations))

  # Apply a complete theme if specified
  if (!is.null(customizations$theme_name)) {
    theme_name <- customizations$theme_name
    # print(paste("[PLOT_CUSTOMIZER] Applying theme:", theme_name))

    # Apply the specified theme
    if (theme_name == "minimal") {
      plot <- plot + ggplot2::theme_minimal()
    } else if (theme_name == "light") {
      plot <- plot + ggplot2::theme_light()
    } else if (theme_name == "classic") {
      plot <- plot + ggplot2::theme_classic()
    } else if (theme_name == "bw") {
      plot <- plot + ggplot2::theme_bw()
    }
  }

  # Apply individual theme elements
  if (!is.null(customizations$theme)) {
    theme_args <- list()

    # Process simple theme elements
    if (!is.null(customizations$theme$background_color)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting background color:", customizations$theme$background_color))
      theme_args$panel.background <- ggplot2::element_rect(fill = customizations$theme$background_color)
    }

    if (!is.null(customizations$theme$grid_color)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting grid color:", customizations$theme$grid_color))
      theme_args$panel.grid.major <- ggplot2::element_line(color = customizations$theme$grid_color)
      theme_args$panel.grid.minor <- ggplot2::element_line(color = customizations$theme$grid_color, linetype = "dashed")
    }

    if (!is.null(customizations$theme$axis_color)) {
      theme_args$axis.line <- ggplot2::element_line(color = customizations$theme$axis_color)
    }

    if (!is.null(customizations$theme$text_family)) {
      theme_args$text <- ggplot2::element_text(family = customizations$theme$text_family)
    }

    if (!is.null(customizations$theme$text_size)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting text size:", customizations$theme$text_size))
      theme_args$text <- ggplot2::element_text(size = customizations$theme$text_size)
    }

    if (!is.null(customizations$theme$legend_position)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting legend position:", customizations$theme$legend_position))
      theme_args$legend.position <- customizations$theme$legend_position
    }

    if (!is.null(customizations$theme$legend_direction)) {
      theme_args$legend.direction <- customizations$theme$legend_direction
    }

    if (!is.null(customizations$theme$legend_box)) {
      theme_args$legend.box <- customizations$theme$legend_box
    }

    # REMOVED: Plot title adjustment (will be handled in UI)
    # REMOVED: Dynamic plot margin (no longer needed for title)

    # Add vertical panel spacing (Keep this)
    # print("[PLOT_CUSTOMIZER] Setting panel spacing y: 1.5 lines")
    theme_args$panel.spacing.y <- ggplot2::unit(1.5, "lines")

    # Add fixed top margin to push facet strips down slightly
    # print("[PLOT_CUSTOMIZER] Setting fixed plot margin (top=15pt)")
    theme_args$plot.margin <- ggplot2::margin(t = 15, r = 10, b = 5, l = 10, unit = "pt")
    # Apply theme modifications
    if (length(theme_args) > 0) {
      # print("[PLOT_CUSTOMIZER] Applying theme modifications")
      plot <- plot + do.call(ggplot2::theme, theme_args)
    }
  }

  # Apply axis formatting
  if (!is.null(customizations$axes)) {
    if (!is.null(customizations$axes$x_title)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting x-axis title:", customizations$axes$x_title))
      plot <- plot + ggplot2::xlab(customizations$axes$x_title)
    }

    if (!is.null(customizations$axes$y_title)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting y-axis title:", customizations$axes$y_title))
      plot <- plot + ggplot2::ylab(customizations$axes$y_title)
    }

    if (!is.null(customizations$axes$x_breaks)) {
      # print("[PLOT_CUSTOMIZER] Setting x-axis breaks")
      plot <- plot + ggplot2::scale_x_continuous(breaks = customizations$axes$x_breaks)
    }

    # Apply custom formatting if specified
    if (!is.null(customizations$axes$x_format)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting x-axis format:", customizations$axes$x_format))
      if (customizations$axes$x_format == "comma") {
        plot <- plot + ggplot2::scale_x_continuous(labels = scales::comma)
      } else if (customizations$axes$x_format == "percent") {
        plot <- plot + ggplot2::scale_x_continuous(labels = scales::percent)
      }
    }

    if (!is.null(customizations$axes$y_format)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting y-axis format:", customizations$axes$y_format))
      if (customizations$axes$y_format == "comma") {
        plot <- plot + ggplot2::scale_y_continuous(labels = scales::comma)
      } else if (customizations$axes$y_format == "percent") {
        plot <- plot + ggplot2::scale_y_continuous(labels = scales::percent)
      }
    }
  }

  # Apply facet customizations
  if (!is.null(customizations$facets)) {
    theme_args <- list() # Re-initialize for facet-specific theme args

    # Remove strip background (set to blank) as a workaround for the manual facet label
    # adjustment in plot_panel.R, which only moves the text, not the background box.
    # print("[PLOT_CUSTOMIZER] Removing facet strip background (setting to element_blank)")
    theme_args$strip.background <- ggplot2::element_blank()
    # if (!is.null(customizations$facets$strip_background)) {
    #   print(paste("[PLOT_CUSTOMIZER] Setting facet strip background:", customizations$facets$strip_background))
    #   theme_args$strip.background <- ggplot2::element_rect(fill = customizations$facets$strip_background)
    # }

    # Combine strip text size and margin settings
    strip_text_args <- list()
    # Check if strip.text element already exists from base theme or other settings
    existing_strip_text <- plot$theme$strip.text %||% ggplot2::element_text()

    # Inherit existing properties
    strip_text_args$family <- existing_strip_text$family
    # Make facet text bold as a replacement styling cue since the background box is removed.
    strip_text_args$face <- "bold"
    strip_text_args$colour <- existing_strip_text$colour
    strip_text_args$hjust <- existing_strip_text$hjust
    strip_text_args$vjust <- existing_strip_text$vjust
    strip_text_args$angle <- existing_strip_text$angle
    # strip_text_args$lineheight <- existing_strip_text$lineheight # Overwrite below

    # Apply size from config if available, otherwise use existing
    if (!is.null(customizations$facets$strip_text_size)) {
      # print(paste("[PLOT_CUSTOMIZER] Setting facet strip text size:", customizations$facets$strip_text_size))
      strip_text_args$size <- customizations$facets$strip_text_size
    } else {
      # Decrease font size slightly if not explicitly set in config
      strip_text_args$size <- existing_strip_text$size * 0.75 # Decrease by 25%
      # print(paste("[PLOT_CUSTOMIZER] Decreasing facet strip text size to:", strip_text_args$size))
    }

    # Apply dynamic margin based on number of lines to accommodate multi-line labels.
    base_vertical_margin <- 3 # Base margin in pt for 1 line
    extra_margin_per_line <- 6 # Reverted extra margin per additional line
    dynamic_vertical_margin <- base_vertical_margin + max(0, num_facet_lines - 1) * extra_margin_per_line
    side_margin <- 10 # Keep increased Horizontal margin

    strip_text_margin <- ggplot2::margin(t = dynamic_vertical_margin, r = side_margin, b = dynamic_vertical_margin, l = side_margin, unit = "pt")
    # print(paste("[PLOT_CUSTOMIZER] Setting dynamic facet strip text margin (t,r,b,l):", dynamic_vertical_margin, side_margin, dynamic_vertical_margin, side_margin, "pt"))
    strip_text_args$margin <- strip_text_margin

    # Increase line height for multi-line labels.
    # Align text to top (vjust=0) to help mitigate clipping issues with ggplotly.
    strip_text_args$vjust <- 0
    # print("[PLOT_CUSTOMIZER] Setting facet strip text vjust: 0")
    strip_text_args$lineheight <- 1.1
    # print("[PLOT_CUSTOMIZER] Setting facet strip text lineheight: 1.1")


    # Assign the combined element_text object
    theme_args$strip.text <- do.call(ggplot2::element_text, strip_text_args)

    # Ensure strips are drawn outside panels (desired layout, despite ggplotly clipping issues).
    theme_args$strip.placement <- "outside"
    # print("[PLOT_CUSTOMIZER] Setting strip.placement: 'outside'")


    # Apply facet theme modifications (strip.background and strip.text)
    # Note: theme_args here is scoped within the 'if (!is.null(customizations$facets))' block
    # We need to apply these specific args to the main plot object
    if (length(theme_args) > 0) {
      # print("[PLOT_CUSTOMIZER] Applying facet theme modifications (strip.background, strip.text, strip.placement)")
      # Create a theme object with only the facet-specific args
      facet_theme <- do.call(ggplot2::theme, theme_args)
      # Add this theme object to the plot
      plot <- plot + facet_theme
    }
  }

  # Debug print to confirm we're returning a valid plot
  # print("[PLOT_CUSTOMIZER] Returning customized plot")
  # print(class(plot))

  return(plot)
}
