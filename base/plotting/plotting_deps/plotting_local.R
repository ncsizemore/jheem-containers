# We need access to the prepare.plot function from PLOTS_simplot.R

library(plotly)
library(yaml) # Added for reading config
# Assuming reshape2 is available, otherwise add library(reshape2)
# library(reshape2) # Add if not loaded elsewhere

# source("R/PLOTS_simplot.R")

# Need access to the Data Manager

# source("R/DATA_MANAGER_data_manager.R")

# Helper function to wrap long axis labels
wrap_axis_label <- function(label, width = 25) {
    if (is.null(label) || is.na(label) || nchar(label) <= width) {
        return(label) # No need to wrap short labels
    }

    # If the label contains units in parentheses, handle them specially
    if (grepl("\\(.*\\)$", label)) {
        # Split into main text and units
        main_text <- gsub("\\s*\\(.*\\)$", "", label)
        units <- gsub("^.*\\((.*)\\)$", "(\\1)", label)

        # Put units on next line
        return(paste0(main_text, "<br>", units))
    }

    # For labels without parenthetical units, split at reasonable points
    words <- strsplit(label, " ")[[1]]
    if (length(words) <= 1) {
        # No spaces to split on, so wrap in the middle
        mid_point <- ceiling(nchar(label) / 2)
        return(paste0(substr(label, 1, mid_point), "<br>", substr(label, mid_point + 1, nchar(label))))
    }

    # Try to split at a space
    result <- ""
    current_line <- words[1]

    for (i in 2:length(words)) {
        word <- words[i]
        if (nchar(current_line) + nchar(word) + 1 <= width) {
            current_line <- paste(current_line, word)
        } else {
            result <- paste0(result, current_line, "<br>")
            current_line <- word
        }
    }

    if (nchar(current_line) > 0) {
        result <- paste0(result, current_line)
    }

    return(result)
}


#' @param ... One or more of either (1) jheem.simulation.set objects or (2) lists containing only jheem.simulation or jheem.simset objects
#' @param outcomes A character vector of which simulation outcomes to plot
#' @param split.by A character vector of dimensions for which to make different lines
#' @param facet.by A character vector of dimensions for which to make different panels
#' @param dimension.values
#' @param data.manager The data.manager from which to draw real-world data for the plots
#' @param style.manager An object of class 'jheem.style.manager' specifying style attributes

plot.simulations_local <- function(...,
                                   outcomes,
                                   corresponding.data.outcomes = NULL,
                                   split.by = NULL,
                                   facet.by = NULL,
                                   dimension.values = list(),
                                   target.ontology = NULL,
                                   summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                                   plot.year.lag.ratio = F,
                                   title = "location",
                                   n.facet.rows = NULL,
                                   interval.coverate = 0.95,
                                   data.manager = get.default.data.manager(),
                                   # style.manager = get.default.style.manager('plotly'),
                                   style.manager = get.default.style.manager(),
                                   hide.legend = FALSE) { # Removed config_path parameter
    plot.which <- "sim.and.data"

    # Load configuration using centralized function
    # Assuming get_component_config is available (sourced elsewhere, e.g., global.R)
    viz_config <- tryCatch(get_component_config("visualization"), error = function(e) {
        warning(paste("Error loading visualization config:", e$message))
        NULL
    })
    config_labels <- if (!is.null(viz_config) && !is.null(viz_config$facet_labels)) {
        viz_config$facet_labels
    } else {
        warning("facet_labels not found in visualization config or config failed to load.")
        list() # Default to empty list
    }

    simset <- list(...)[[1]]

    # plot.data.validation might need to become local too if it's not accessible
    # For now, assume it's available globally or sourced
    plot.data <- plot.data.validation(
        list(...),
        match.call(expand.dots = F)$...,
        outcomes,
        corresponding.data.outcomes,
        plot.which,
        summary.type
    )

    # These values are possibly modified by the plot.data.validation call, so
    # they need to be extracted from the returned list.
    simset.list <- plot.data$simset.list
    outcomes <- plot.data$outcomes # Make sure outcomes is updated if validation modifies it

    # Call the original prepare.plot function (ensure it's accessible)
    # Make sure append.url is NOT set to T
    prepared.plot.data <- prepare.plot(simset.list,
        outcomes = outcomes,
        locations = NULL,
        corresponding.data.outcomes = corresponding.data.outcomes,
        split.by = split.by,
        facet.by = facet.by,
        dimension.values = dimension.values,
        target.ontology = target.ontology,
        plot.which = plot.which,
        summary.type = summary.type,
        plot.year.lag.ratio = plot.year.lag.ratio,
        title = title,
        # append.url = F, # Explicitly false or omitted
        data.manager = data.manager,
        style.manager = style.manager, # Pass style manager
        # show.data.pull.error = F, # Pass if needed
        debug = F
    )

    execute.plotly.plot_local(prepared.plot.data,
        outcomes = outcomes, # Pass the potentially updated outcomes
        split.by = split.by,
        facet.by = facet.by,
        plot.which = plot.which,
        summary.type = summary.type,
        plot.year.lag.ratio = plot.year.lag.ratio,
        n.facet.rows = n.facet.rows,
        style.manager = style.manager,
        debug = debug,
        hide.legend = hide.legend,
        config_labels = config_labels # Pass loaded labels
    )
}

# Removed prepare.plot_local function definition

#--------------------------------------#
#-- execute.plotly.plot_local function --#
#--------------------------------------#

execute.plotly.plot_local <- function(prepared.plot.data,
                                      outcomes = NULL,
                                      split.by = NULL,
                                      facet.by = NULL,
                                      plot.which = "sim.and.data",
                                      summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                                      plot.year.lag.ratio = F,
                                      n.facet.rows = NULL,
                                      style.manager = get.default.style.manager(),
                                      debug = F,
                                      hide.legend = FALSE,
                                      config_labels = list()) { # Added config_labels parameter
    # Extract data from prepared.plot.data
    df.sim <- prepared.plot.data$df.sim
    df.truth <- prepared.plot.data$df.truth
    y.label <- prepared.plot.data$details$y.label
    plot.title <- prepared.plot.data$details$plot.title
    outcome.metadata <- prepared.plot.data$details$outcome.metadata.list # Use list from details
    sim.labels.list <- prepared.plot.data$details$sim.labels.list # Extract sim labels

    #-- PREPARE PLOT COLORS, SHADES, SHAPES, ETC. --#
    if (!is.null(df.sim)) {
        # Ensure style columns exist before assignment
        if (!style.manager$linetype.sim.by %in% names(df.sim)) df.sim[[style.manager$linetype.sim.by]] <- ""
        if (!style.manager$shape.sim.by %in% names(df.sim)) df.sim[[style.manager$shape.sim.by]] <- ""
        if (!style.manager$color.sim.by %in% names(df.sim)) df.sim[[style.manager$color.sim.by]] <- ""

        df.sim["linetype.sim.by"] <- df.sim[style.manager$linetype.sim.by]
        df.sim["shape.sim.by"] <- df.sim[style.manager$shape.sim.by]
        df.sim["color.sim.by"] <- df.sim[style.manager$color.sim.by]
    }

    if (!is.null(df.truth)) {
        # Ensure style columns exist before assignment
        if (!style.manager$shape.data.by %in% names(df.truth)) df.truth[[style.manager$shape.data.by]] <- ""
        if (!style.manager$color.data.by %in% names(df.truth)) df.truth[[style.manager$color.data.by]] <- ""
        if (!style.manager$shade.data.by %in% names(df.truth)) df.truth[[style.manager$shade.data.by]] <- ""
        if (!"stratum" %in% names(df.truth)) df.truth[["stratum"]] <- "" # Ensure stratum exists for logic below

        # make some other columns
        # Assuming locations::get.location.type is available
        if (requireNamespace("locations", quietly = TRUE) && "location" %in% names(df.truth)) {
            df.truth["location.type"] <- locations::get.location.type(df.truth$location)
        } else {
            df.truth["location.type"] <- NA # Or handle missing dependency/column
        }
        df.truth["shape.data.by"] <- df.truth[style.manager$shape.data.by]
        df.truth["color.data.by"] <- df.truth[style.manager$color.data.by]
        df.truth["shade.data.by"] <- df.truth[style.manager$shade.data.by]
        if (style.manager$color.data.by == "stratum" && !is.null(df.truth$stratum) && all(df.truth$stratum == "")) {
            df.truth["color.and.shade.data.by"] <- df.truth["shade.data.by"]
        } else if (style.manager$shade.data.by == "stratum" && !is.null(df.truth$stratum) && all(df.truth$stratum == "")) {
            df.truth["color.and.shade.data.by"] <- df.truth["color.data.by"]
        } else {
            # Ensure columns exist before pasting
            shade_col <- df.truth[[style.manager$shade.data.by]]
            color_col <- df.truth[[style.manager$color.data.by]]
            if (!is.null(shade_col) && !is.null(color_col)) {
                df.truth["color.and.shade.data.by"] <- paste(shade_col, color_col, sep = "__")
            } else {
                df.truth["color.and.shade.data.by"] <- NA # Handle missing columns
            }
        }
    }

    ## GROUPS (Split sim data for line vs point rendering)
    df.sim.groupids.one.member <- NULL
    df.sim.groupids.many.members <- NULL
    if (!is.null(df.sim)) {
        # Ensure groupid exists
        if (!"groupid" %in% names(df.sim)) {
            # Ensure required columns for interaction exist
            req_cols <- c("outcome", "simset", "sim", "stratum")
            missing_req <- setdiff(req_cols, names(df.sim))
            if (length(missing_req) > 0) stop(paste("Missing columns required for groupid:", paste(missing_req, collapse = ", ")))

            df.sim$groupid <- interaction(df.sim$outcome, df.sim$simset, df.sim$sim, df.sim$stratum %||% "", sep = "_")
        }

        groupids.with.one.member <- setdiff(unique(df.sim$groupid), df.sim$groupid[which(duplicated(df.sim$groupid))])
        df.sim$groupid_has_one_member <- with(df.sim, groupid %in% groupids.with.one.member)
        df.sim.groupids.one.member <- subset(df.sim, groupid_has_one_member)
        df.sim.groupids.many.members <- subset(df.sim, !groupid_has_one_member)
    }

    plotly.debug <- FALSE

    ## COLORS
    colors.for.sim <- NULL
    color.data.primary.colors <- NULL

    sim.color.groups <- if (!is.null(df.sim)) sort(unique(df.sim$color.sim.by)) else character(0)
    data.color.groups <- if (!is.null(df.truth)) sort(unique(df.truth$color.data.by)) else character(0)

    # if coloring by the same thing, use the same palette (defaulting to SIM's palette) unless one is missing
    if (style.manager$color.sim.by == style.manager$color.data.by) {
        all.color.groups <- sort(union(sim.color.groups, data.color.groups))

        if (length(all.color.groups) > 0) {
            if (!is.null(df.sim)) {
                all.colors <- style.manager$get.sim.colors(length(all.color.groups))
            } else if (!is.null(df.truth)) {
                all.colors <- style.manager$get.data.colors(length(all.color.groups))
            } else {
                all.colors <- NULL
            }
            if (!is.null(all.colors)) names(all.colors) <- all.color.groups
            colors.for.sim <- all.colors[sim.color.groups]
            color.data.primary.colors <- all.colors[data.color.groups]
        }
    } else { # otherwise, assign colors individually
        if (length(sim.color.groups) > 0) {
            colors.for.sim <- style.manager$get.sim.colors(length(sim.color.groups))
            names(colors.for.sim) <- sim.color.groups
        }
        if (length(data.color.groups) > 0) {
            color.data.primary.colors <- style.manager$get.data.colors(length(data.color.groups))
            names(color.data.primary.colors) <- data.color.groups
        }
    }

    ## RIBBON COLOR
    color.ribbon.by <- NULL
    if (!is.null(df.sim) && length(colors.for.sim) > 0) {
        # Ensure names match before applying alpha
        valid_colors_for_ribbon <- colors.for.sim[!is.na(names(colors.for.sim))]
        if (length(valid_colors_for_ribbon) > 0) {
            color.ribbon.by <- ggplot2::alpha(valid_colors_for_ribbon, style.manager$alpha.ribbon)
            # Make sure names are preserved if alpha returns unnamed vector for single color
            if (is.null(names(color.ribbon.by)) && length(valid_colors_for_ribbon) == 1) {
                names(color.ribbon.by) <- names(valid_colors_for_ribbon)
            }
        }
    }

    ## SHADES FOR DATA
    color.data.shaded.colors <- NULL
    if (!is.null(df.truth) && length(color.data.primary.colors) > 0) {
        shade.data.groups <- unique(df.truth$shade.data.by)
        if (length(shade.data.groups) > 0) {
            color.data.shaded.colors <- unlist(lapply(color.data.primary.colors, function(prim.color) {
                style.manager$get.shades(base.color = prim.color, length(shade.data.groups))
            }))
            # This can lead to problems if we have either of these being "" because then we'll get an underscore that won't match the actual column values in the data frame
            if (identical(unique(df.truth$color.data.by), "")) {
                names(color.data.shaded.colors) <- shade.data.groups
            } else {
                # Ensure expand.grid inputs are unique factors/characters
                shade_levels <- unique(as.character(df.truth$shade.data.by))
                color_levels <- unique(as.character(df.truth$color.data.by))
                if (length(shade_levels) > 0 && length(color_levels) > 0) {
                    name_grid <- expand.grid(shade_levels, color_levels)
                    names(color.data.shaded.colors) <- do.call(paste, c(name_grid, list(sep = "__")))
                }
            }
        }
    }

    ## SHAPES
    shapes.for.data <- NULL
    shapes.for.sim <- NULL
    data.shape.groups <- if (!is.null(df.truth)) unique(df.truth$shape.data.by) else character(0)
    sim.shape.groups <- if (!is.null(df.sim)) unique(df.sim$shape.sim.by) else character(0)

    if (length(data.shape.groups) > 0) {
        shapes.for.data <- style.manager$get.shapes(length(data.shape.groups))
        names(shapes.for.data) <- data.shape.groups
    }
    if (length(sim.shape.groups) > 0) {
        shapes.for.sim <- style.manager$get.shapes(length(sim.shape.groups))
        names(shapes.for.sim) <- sim.shape.groups
    }
    all.shapes.for.scale <- c(shapes.for.data, shapes.for.sim)

    ## LINETYPES
    linetypes.for.sim <- NULL
    sim.linetype.groups <- if (!is.null(df.sim)) unique(df.sim$linetype.sim.by) else character(0)
    if (length(sim.linetype.groups) > 0) {
        linetypes.for.sim <- style.manager$get.linetypes(length(sim.linetype.groups))
        names(linetypes.for.sim) <- sim.linetype.groups
        # Convert ggplot linetypes to plotly dash types
        linetypes.for.sim <- gsub("dashed", "dash", linetypes.for.sim)
        linetypes.for.sim <- gsub("dotted", "dot", linetypes.for.sim)
        linetypes.for.sim <- gsub("solid", "solid", linetypes.for.sim) # Ensure solid maps correctly
    }

    # Mapping the ggplot marker shapes into plotly symbols
    marker.mappings <- unlist(lapply(shapes.for.data, function(gg_shape) {
        if (gg_shape == 21) {
            return("circle")
        }
        if (gg_shape == 22) {
            return("square")
        }
        if (gg_shape == 23) {
            return("diamond")
        }
        if (gg_shape == 24) {
            return("triangle-up")
        }
        if (gg_shape == 25) {
            return("triangle-down")
        }
        # Add more mappings if other shapes are used
        return("circle") # Default
    }))

    # Legend handling variables
    trace.in.legend <- list()

    # Add line colors/styles to simulation data
    if (!is.null(df.sim.groupids.many.members) && nrow(df.sim.groupids.many.members) > 0) {
        df.sim.groupids.many.members$line.color <-
            unlist(lapply(df.sim.groupids.many.members$color.sim.by, function(val) {
                # Provide default if val is NA, NULL, "", or not in names
                if (is.null(val) || is.na(val) || val == "" || is.null(colors.for.sim[[val]])) {
                    style.manager$get.sim.colors(1)
                } else {
                    colors.for.sim[[val]]
                }
            }))
        df.sim.groupids.many.members$line.shape <-
            unlist(lapply(df.sim.groupids.many.members$linetype.sim.by, function(val) {
                # Provide default if val is NA, NULL, "", or not in names
                if (is.null(val) || is.na(val) || val == "" || is.null(linetypes.for.sim[[val]])) {
                    "solid"
                } else {
                    linetypes.for.sim[[val]]
                }
            }))
    }

    # Add marker shape/color info to truth data
    if (!is.null(df.truth) && nrow(df.truth) > 0) {
        # Ensure shape.data.by and color.data.by exist before using them
        if (!"shape.data.by" %in% names(df.truth)) df.truth$shape.data.by <- ""
        if (!"color.data.by" %in% names(df.truth)) df.truth$color.data.by <- ""

        df.truth$marker.shapes <- unlist(lapply(df.truth$shape.data.by, function(val) {
            # Default shape if val is invalid or mapping missing
            if (is.null(val) || is.na(val) || val == "" || is.null(marker.mappings[[val]])) {
                "circle"
            } else {
                marker.mappings[[val]]
            }
        }))
        df.truth$marker.colors <- unlist(lapply(df.truth$color.data.by, function(val) {
            # Default color if val is invalid or mapping missing
            if (is.null(val) || is.na(val) || val == "" || is.null(color.data.primary.colors[[val]])) {
                "#000000"
            } else {
                color.data.primary.colors[[val]]
            }
        }))
    }

    # Determine combined faceting columns and create interaction term
    # Use facet.by if provided, otherwise only 'outcome'
    facet_cols_to_use <- if (!is.null(facet.by)) c("outcome", facet.by) else "outcome"
    combined_facet_col <- "combined_facet"
    all_combined_facets <- character(0) # Initialize empty vector

    # Helper function to safely create interaction term
    create_interaction <- function(df, cols, new_col_name) {
        # Check if all columns exist
        missing_cols <- setdiff(cols, names(df))
        if (length(missing_cols) > 0) {
            # Check if missing cols are generated facet.byX cols
            # prepare.plot_local renames facet.by columns to facet.by1, facet.by2 etc.
            # We need to use those generated names if they exist
            generated_facet_cols <- grep("^facet\\.by[0-9]+$", names(df), value = TRUE)
            original_facet_by_cols <- setdiff(cols, "outcome") # Get the original facet.by names requested

            # Check if the number of generated cols matches the number requested
            if (length(original_facet_by_cols) > 0 && length(generated_facet_cols) == length(original_facet_by_cols)) {
                cols_to_interact <- c("outcome", generated_facet_cols)
                # Final check if these generated columns actually exist
                missing_generated <- setdiff(cols_to_interact, names(df))
                if (length(missing_generated) > 0) {
                    stop(paste("Missing required generated faceting columns:", paste(missing_generated, collapse = ", ")))
                }
            } else {
                # If it's not the generated columns case, or numbers don't match, it's an error
                stop(paste("Missing required faceting columns:", paste(missing_cols, collapse = ", ")))
            }
        } else {
            # All original columns exist (e.g., if facet.by was NULL or only 'outcome')
            cols_to_interact <- cols
        }
        # Create interaction term using the determined columns
        # Ensure columns exist before interaction
        if (!all(cols_to_interact %in% names(df))) {
            stop(paste("Interaction columns not found in data frame:", paste(setdiff(cols_to_interact, names(df)), collapse = ", ")))
        }
        df[[new_col_name]] <- interaction(df[, cols_to_interact, drop = FALSE], sep = " | ")
        return(df)
    }

    # Apply interaction term to all relevant data frames
    if (!is.null(df.sim)) {
        df.sim <- create_interaction(df.sim, facet_cols_to_use, combined_facet_col)
        all_combined_facets <- union(all_combined_facets, unique(df.sim[[combined_facet_col]]))

        # Also apply to one_member/many_members df if they exist
        if (!is.null(df.sim.groupids.one.member) && nrow(df.sim.groupids.one.member) > 0) {
            df.sim.groupids.one.member <- create_interaction(df.sim.groupids.one.member, facet_cols_to_use, combined_facet_col)
        }
        if (!is.null(df.sim.groupids.many.members) && nrow(df.sim.groupids.many.members) > 0) {
            df.sim.groupids.many.members <- create_interaction(df.sim.groupids.many.members, facet_cols_to_use, combined_facet_col)
        }
    }

    if (!is.null(df.truth)) {
        df.truth <- create_interaction(df.truth, facet_cols_to_use, combined_facet_col)
        all_combined_facets <- union(all_combined_facets, unique(df.truth[[combined_facet_col]]))
    }

    # Calculate final facet categories and count
    facet.categories <- sort(unique(as.character(all_combined_facets))) # Ensure character and unique
    figure.count <- length(facet.categories)

    # Helper function to extract outcome from facet string
    outcome_from_facet <- function(facet_str) {
        strsplit(as.character(facet_str), " | ", fixed = TRUE)[[1]][1]
    }

    # Ensure outcome.metadata names are accessible and match outcomes vector
    # Use the outcome.metadata list directly from prepared.plot.data$details
    if (is.null(names(outcome.metadata)) || !all(outcomes %in% names(outcome.metadata))) {
        # Attempt to fix names if possible, otherwise warn
        if (length(outcome.metadata) == length(outcomes)) {
            names(outcome.metadata) <- outcomes
            warning("Outcome metadata was unnamed; assigned names based on 'outcomes' parameter.")
        } else {
            warning("Outcome metadata names are missing or do not match 'outcomes'. Y-axis labels may be incorrect.")
        }
    }

    # Helper for properly creating the y.axis labels for the figures
    y.axis.label.helper <- function(outcome.metadata, outcome) {
        # Check if outcome exists in metadata
        if (!outcome %in% names(outcome.metadata)) {
            warning(paste("Outcome", outcome, "not found in outcome.metadata. Using outcome name as label."))
            return(outcome)
        }
        meta <- outcome.metadata[[outcome]]
        # Check for expected fields, provide defaults if missing
        label <- meta$axis.name %||% meta$display.name %||% outcome # Fallback label logic
        unit <- meta$units %||% ""
        # We want to prevent a 'Cases (cases)' situation here
        if (unit != "" && tolower(label) == tolower(unit)) {
            return(label)
        } else if (unit != "") {
            return(paste0(label, " (", unit, ")"))
        } else {
            return(label) # No unit to add
        }
    }

    # Create vector of y-axis labels for each facet
    y_axis_labels <- sapply(facet.categories, function(cat) {
        outcome_name <- outcome_from_facet(cat)
        if (!outcome_name %in% names(outcome.metadata)) {
            warning(paste("Outcome", outcome_name, "from facet category not found in outcome.metadata. Using outcome name as label."))
            return(outcome_name) # Use outcome name as fallback label
        }
        y.axis.label.helper(outcome.metadata, outcome_name)
    }, USE.NAMES = TRUE)
    names(y_axis_labels) <- facet.categories

    # Calculate global year range across both datasets
    all_years <- c()
    if (!is.null(df.sim) && "year" %in% names(df.sim)) {
        all_years <- c(all_years, df.sim$year)
    }
    if (!is.null(df.truth) && "year" %in% names(df.truth)) {
        all_years <- c(all_years, df.truth$year)
    }

    global_year_range <- NULL
    if (length(all_years) > 0) {
        # Ensure years are numeric and remove NA/Inf before calculating range
        numeric_years <- suppressWarnings(as.numeric(all_years))
        valid_years <- numeric_years[!is.na(numeric_years) & is.finite(numeric_years)]
        if (length(valid_years) > 0) {
            global_year_range <- range(valid_years)
        }
    }

    # Helper function for creating a single facet plot with all traces
    create_facet_plot <- function(facet_name, facet_data, truth_data, y_axis_title, hide.legend = FALSE, config_labels = list()) { # Pass config_labels
        # --- Create Nice Facet Title ---
        facet_components <- strsplit(as.character(facet_name), " | ", fixed = TRUE)[[1]]
        nice_facet_components <- character(length(facet_components))
        facet_dimension_names <- if (!is.null(facet.by)) facet.by else character(0) # Get original facet.by names

        # First component is always outcome
        outcome_component <- facet_components[1]
        # Check if outcome component exists before accessing
        if (outcome_component %in% names(outcome.metadata)) {
            nice_facet_components[1] <- outcome.metadata[[outcome_component]]$display.name %||% outcome_component
        } else {
            # Fallback if outcome not in metadata (shouldn't happen ideally)
            nice_facet_components[1] <- outcome_component
        }

        # Subsequent components are facet dimensions (use config_labels)
        if (length(facet_components) > 1 && length(facet_dimension_names) == (length(facet_components) - 1)) {
            for (i in 2:length(facet_components)) {
                dimension_index <- i - 1 # Index into facet_dimension_names
                dimension_name <- facet_dimension_names[dimension_index]
                facet_value <- facet_components[i]

                # Check if dimension exists in config_labels and value exists within that dimension
                lookup_result <- NULL
                if (dimension_name %in% names(config_labels) && facet_value %in% names(config_labels[[dimension_name]])) {
                    lookup_result <- config_labels[[dimension_name]][[facet_value]]
                }

                # Fallback to sim.labels.list if not found in config (optional, but keeps outcome label logic)
                if (is.null(lookup_result) && !is.null(sim.labels.list) && length(sim.labels.list) > 0) {
                    labels_from_sim <- sim.labels.list[[1]] # Assuming first simset's labels
                    if (is.character(labels_from_sim) && !is.null(names(labels_from_sim))) {
                        matched_index <- match(facet_value, names(labels_from_sim))
                        if (!is.na(matched_index)) {
                            lookup_result <- labels_from_sim[matched_index]
                        }
                    }
                }

                # Use lookup result or fallback to original value
                nice_facet_components[i] <- lookup_result %||% facet_value
            }
        } else if (length(facet_components) > 1) {
            # Fallback if dimension names don't align (shouldn't happen ideally)
            warning("Mismatch between facet components and facet.by names. Using raw values.")
            nice_facet_components[2:length(facet_components)] <- facet_components[2:length(facet_components)]
        }

        nice_facet_title_raw <- paste(nice_facet_components, collapse = " | ")
        # Wrap the title using the existing helper function (adjust width if needed)
        nice_facet_title_wrapped <- wrap_axis_label(nice_facet_title_raw, width = 40) # Increased width slightly for titles
        # --- End Nice Facet Title ---

        # Initialize plot with annotations instead of title
        p <- plot_ly() %>%
            layout(

                # Use annotations for the title
                annotations = list(
                    list(
                        text = nice_facet_title_wrapped, # Use the wrapped title
                        x = 0.5, # Center horizontally
                        y = 1.05, # Slightly above the plot
                        xref = "paper", # Use paper coordinates
                        yref = "paper", # Use paper coordinates
                        showarrow = FALSE,
                        font = list(size = 12, weight = "bold"),
                        xanchor = "center",
                        yanchor = "bottom"
                    )
                ),
                xaxis = list(
                    title = list(text = "Years", standoff = 5)
                ),
                yaxis = list(
                    title = list(
                        text = wrap_axis_label(y_axis_title, width = 25), # Apply wrapping
                        standoff = 10
                    ),
                    automargin = TRUE, # Allow plotly to adjust margin for labels
                    fixedrange = FALSE # Allow y-axis scaling
                ),
                # Increased top margin for potentially wrapped facet titles
                margin = list(t = 50, b = 10, l = 70, r = 10)
            )

        # Apply global year range if available
        if (!is.null(global_year_range)) {
            p <- p %>% layout(xaxis = list(range = global_year_range))
        }

        # Process simulation data (with ribbons)
        if (!is.null(facet_data) && nrow(facet_data) > 0) {
            # For each unique group, add traces
            groupids <- unique(facet_data$groupid)

            for (group_id in groupids) {
                # Get data for this group
                group_data <- facet_data[facet_data$groupid == group_id, ]
                if (nrow(group_data) == 0) next

                # Check if this group has ribbon data
                has_ribbon <- "value.upper" %in% names(group_data) &&
                    "value.lower" %in% names(group_data) &&
                    any(!is.na(group_data$value.upper)) &&
                    any(!is.na(group_data$value.lower))

                # Determine visual attributes
                col <- group_data$line.color[1] %||% "#000000"
                linetype <- group_data$line.shape[1] %||% "solid"

                # Add to legend only once per color/linetype combination
                trace.key <- paste(col, linetype, sep = "_")
                show_in_legend <- FALSE
                if (!hide.legend && is.null(trace.in.legend[[trace.key]])) {
                    show_in_legend <- TRUE
                    trace.in.legend[[trace.key]] <<- TRUE
                }

                # Order data by year for ribbon drawing
                group_data <- group_data[order(group_data$year), ]

                # Add ribbon if present
                if (has_ribbon) {
                    # Find ribbon color
                    ribbon_color_name <- group_data$color.sim.by[1]
                    fill_color <- if (!is.null(color.ribbon.by) &&
                        ribbon_color_name %in% names(color.ribbon.by)) {
                        color.ribbon.by[[ribbon_color_name]]
                    } else {
                        "rgba(128,128,128,0.2)" # Default transparent grey
                    }

                    # Add upper bound trace
                    p <- p %>% add_trace(
                        x = group_data$year,
                        y = group_data$value.upper,
                        type = "scatter",
                        mode = "lines",
                        line = list(width = 0),
                        showlegend = FALSE,
                        hoverinfo = "skip",
                        name = paste0(group_id, ".upper")
                    )

                    # Add lower bound trace with fill
                    p <- p %>% add_trace(
                        x = group_data$year,
                        y = group_data$value.lower,
                        type = "scatter",
                        mode = "lines",
                        line = list(width = 0),
                        fill = "tonexty",
                        fillcolor = fill_color,
                        showlegend = FALSE,
                        hoverinfo = "skip",
                        name = paste0(group_id, ".lower")
                    )
                }

                # Add main line trace
                p <- p %>% add_trace(
                    x = group_data$year,
                    y = group_data$value,
                    type = "scatter",
                    mode = "lines",
                    line = list(color = col, dash = linetype),
                    showlegend = show_in_legend,
                    name = group_data$simset[1], # Use simset for legend
                    hoverinfo = "text",
                    text = paste("Year:", group_data$year, "<br>Value:", round(group_data$value, 2))
                )
            }
        }

        # Process truth data (markers)
        if (!is.null(truth_data) && nrow(truth_data) > 0) {
            # Group by shape and color for efficient trace creation
            unique_shapes <- unique(truth_data$marker.shapes)

            for (shape in unique_shapes) {
                shape_data <- truth_data[truth_data$marker.shapes == shape, ]
                unique_colors <- unique(shape_data$marker.colors)

                for (color in unique_colors) {
                    point_data <- shape_data[shape_data$marker.colors == color, ]
                    if (nrow(point_data) == 0) next

                    # Determine if should show in legend
                    marker_key <- paste("truth", color, shape, sep = "_")
                    show_in_legend <- FALSE
                    if (!hide.legend && is.null(trace.in.legend[[marker_key]])) {
                        show_in_legend <- TRUE
                        trace.in.legend[[marker_key]] <<- TRUE
                    }

                    # Add marker trace
                    p <- p %>% add_trace(
                        x = point_data$year,
                        y = point_data$value,
                        type = "scatter",
                        mode = "markers",
                        marker = list(
                            color = color,
                            symbol = shape,
                            line = list(color = "#202020", width = 1)
                        ),
                        showlegend = show_in_legend,
                        name = "Observed Data",
                        hoverinfo = "text",
                        text = paste(
                            "Year:", point_data$year,
                            "<br>Value:", round(point_data$value, 2),
                            if ("data.source" %in% names(point_data)) paste("<br>Source:", point_data$data.source) else "",
                            # Add URL if available and not empty using ifelse for row-wise check
                            ifelse("url" %in% names(point_data) & !is.na(point_data$url) & nzchar(point_data$url), paste("<br>URL:", point_data$url), "")
                        )
                    )
                }
            }
        }

        return(p)
    }

    # --- Load Facet Configuration ---
    vis_config <- tryCatch(get_component_config("visualization"), error = function(e) NULL)
    facet_config <- vis_config$faceted_plots %||% list()

    # Set defaults if not configured
    min_facet_width <- facet_config$min_facet_width %||% 350 # Not used in height calc, but good practice
    min_facet_height <- facet_config$min_facet_height %||% 250
    max_columns <- facet_config$max_columns %||% 2
    # --- End Facet Configuration ---

    # Create a list to hold individual facet plots
    plot_list <- list()

    # Create a single plot for each facet
    for (facet_name in facet.categories) {
        # Get simulation data for this facet
        sim_data <- NULL
        if (!is.null(df.sim.groupids.many.members) && nrow(df.sim.groupids.many.members) > 0) {
            sim_data <- subset(
                df.sim.groupids.many.members,
                as.character(df.sim.groupids.many.members[[combined_facet_col]]) == as.character(facet_name)
            )
        }

        # Get truth data for this facet
        truth_data <- NULL
        if (!is.null(df.truth) && nrow(df.truth) > 0) {
            truth_data <- subset(
                df.truth,
                as.character(df.truth[[combined_facet_col]]) == as.character(facet_name)
            )
        }

        # Get y-axis title for this facet
        y_axis_title <- y_axis_labels[facet_name]

        # Create the facet plot, passing config_labels
        plot_list[[facet_name]] <- create_facet_plot(facet_name, sim_data, truth_data, y_axis_title, hide.legend, config_labels)
    }

    # Calculate layout grid and create final plot
    if (length(plot_list) > 1) {
        # Use max_columns from config
        plot.cols <- min(max_columns, length(plot_list))
        # Calculate rows based on column count (Corrected calculation)
        plot.rows <- ceiling(length(plot_list) / plot.cols)

        # Simple height calculation - fixed height per facet row
        # Add some buffer for title, legend, margins
        subplot_height <- (plot.rows * min_facet_height) + 150 # Added 150px buffer

        # Use vector margins for better control of spacing between subplots
        subplot_margin <- c(0.05, 0.1, 0.05, 0.1) # top, right, bottom, left margins

        # Combine plots with subplot
        final_plot <- subplot(
            plotlist = plot_list,
            nrows = plot.rows,
            shareX = TRUE,
            shareY = FALSE, # Keep Y axes independent for different outcomes/scales
            margin = subplot_margin
        ) %>% layout(
            autosize = TRUE, # Tell plotly to try and fit container
            title = list(text = plot.title),
            height = subplot_height, # Set dynamic height
            showlegend = !hide.legend,
            legend = list(
                orientation = "h",
                y = 1.05, # Position above the plot
                x = 0.5,
                xanchor = "center",
                yanchor = "bottom",
                traceorder = "normal",
                itemsizing = "constant"
            ),
            # Adjust margins: Increased top for legend/title, further increased left margin
            margin = list(t = 100, b = 50, l = 100, r = 20)
        )
    } else if (length(plot_list) == 1) {
        # If only one plot, just add the main title
        # The plot created by create_facet_plot already has the title as annotation
        final_plot <- plot_list[[1]] %>% layout(
            title = list(text = plot.title), # Add main plot title
            showlegend = !hide.legend,
            legend = list(
                orientation = "h",
                y = -0.1,
                x = 0.5,
                xanchor = "center",
                traceorder = "normal",
                itemsizing = "constant"
            ),
            margin = list(t = 70, b = 80, l = 50, r = 20)
        )
    } else {
        # No plots - create empty plot with message
        final_plot <- plot_ly() %>% layout(
            title = list(text = "No data to display"),
            xaxis = list(visible = FALSE),
            yaxis = list(visible = FALSE)
        )
    }

    # Print basic info about the plot
    return(final_plot)
}
