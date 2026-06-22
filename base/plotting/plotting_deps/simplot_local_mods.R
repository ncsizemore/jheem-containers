library(tidyr)
library(dplyr)

#' @title Plot Simulations And Data
#' @param ... One or more jheem.simulation.set objects and at most one character vector of outcomes (as an alternative to the 'outcomes' argument)
#' @param corresponding.data.outcomes Specify directly which data outcomes should be plotted against simulation outcomes. Must be NULL or a character vector with outcomes as names; all of those outcomes must be present in either the 'outcomes' argument or in '...'"
#' @param outcomes A character vector of which simulation outcomes to plot
#' @param split.by At most one dimension
#' @param facet.by Any number of dimensions but cannot include the split.by dimension
#' @param dimension.values
#' @param plot.which Should simulation data and calibration data be plotted ('sim.and.data'), or only simulation data ('sim.only')
#' @param title NULL or a single, non-NA character value. If "location", the location of the first provided simset (if any) will be used for the title.
#' @param data.manager The data.manager from which to draw real-world data for the plots
#' @param style.manager We are going to have to define this down the road. It's going to govern how we do lines and sizes and colors. For now, just hard code those in, and we'll circle back to it
#' @param show.data.pull.error Not finding data does not block the plot from showing simulation projections, but if you'd like to see in error when data doesn't appear, set this to TRUE.
#'
#' @details Returns a ggplot object:
#'  - With one panel for each combination of outcome x facet.by
#'  - x-axis is year
#'  - y-axis is outcome
#'
#' @export
simplot_local <- function(...,
                          outcomes = NULL,
                          corresponding.data.outcomes = NULL,
                          split.by = NULL,
                          facet.by = NULL,
                          dimension.values = list(),
                          target.ontology = NULL,
                          plot.which = c("sim.and.data", "sim.only")[1],
                          summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                          plot.year.lag.ratio = F,
                          title = "location",
                          n.facet.rows = NULL,
                          append.url = F,
                          data.manager = get.default.data.manager(),
                          style.manager = get.default.style.manager(),
                          show.data.pull.error = F,
                          facet_labeller = NULL, # NEW: Optional labeller function
                          debug = F) {
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
    outcomes <- plot.data$outcomes

    prepared.plot.data <- prepare_plot_local(simset.list,
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
        append.url = append.url,
        data.manager = data.manager,
        style.manager = style.manager,
        show.data.pull.error = show.data.pull.error,
        debug = debug
    )

    execute_simplot_local(prepared.plot.data,
        outcomes = outcomes,
        split.by = split.by,
        facet.by = facet.by,
        plot.which = plot.which,
        summary.type = summary.type,
        plot.year.lag.ratio = plot.year.lag.ratio,
        n.facet.rows = n.facet.rows,
        style.manager = style.manager,
        facet_labeller = facet_labeller, # Pass down the labeller
        debug = debug
    )
}

#' Cleaning and verifying the plotting data so it can be properly plotted
#' @param simset.args A list of the ... parameter in the previous function, containing simset data.  Will be processed and returned as $simset.list
#' @param deparsed.substituted.args.simset.args The ... parameter with each argument converted to a character exactly as it is, without evaluating any expressions. Used to give un-named simsets names later.
#' @param outcomes The outcomes asked for by the plotting function.  Will be processed and returned as $outcomes
#' @param corresponding.data.outcomes Checked for proper value, not passed out of the function
#' @param plot.which Checked for proper value, not passed out of the function
#' @param summary.type Checked for proper value, not passed out of the function
#' @return A list containing processed $simset.list and $outcomes (a vector)
#' @export
plot.data.validation <- function(simset.args,
                                 deparsed.substituted.args.simset.args,
                                 outcomes,
                                 corresponding.data.outcomes,
                                 plot.which,
                                 summary.type) {
    rv <- list()

    error.prefix <- "Cannot generate simplot: "

    if (!(identical(plot.which, "sim.and.data") || identical(plot.which, "sim.only"))) {
        stop(paste0(error.prefix, "'plot.which' must be either 'sim.and.data' or 'sim.only'"))
    }

    if (!(identical(summary.type, "individual.simulation") || identical(summary.type, "mean.and.interval") || identical(summary.type, "median.and.interval"))) {
        stop(paste0(error.prefix, "'summary.type' must be one of 'individual.simulation', 'mean.and.interval', or 'median.and.interval'"))
    }

    # *corresponding.data.outcomes' is NULL or a vector with outcomes as names
    if (!is.null(corresponding.data.outcomes) && (!is.character(corresponding.data.outcomes) || any(is.na(corresponding.data.outcomes)) || is.null(names(corresponding.data.outcomes)) || !all(names(corresponding.data.outcomes) %in% outcomes))) {
        stop(paste0(error.prefix, "'corresponding.data.outcomes' must be NULL or a character vector with outcomes as names and all of those outcomes specified in either the 'outcomes' argument or in '...'"))
    }

    # each element of 'sim.list' should be a simset
    arg.is.simset <- sapply(simset.args, function(element) {
        if (!R6::is.R6(element) || !is(element, "jheem.simulation.set")) {
            if (is.character(element)) {
                return(FALSE)
            } else {
                stop(paste0(error.prefix, "arguments supplied in '...' must be jheem.simulation.set objects and at most one character vector of outcomes"))
            }
        }
        return(TRUE)
    })

    # Pull out outcomes, which may be at most one element of the ...
    rv$outcomes <- outcomes
    if (sum(!arg.is.simset) > 0) {
        if (!is.null(outcomes)) {
            stop(paste0(error.prefix, "outcomes must be specified either in '...' arguments or in the 'outcomes' argument, but not both"))
        }
        if (sum(!arg.is.simset) > 1) {
            stop(paste0(error.prefix, "at most one character vector of outcomes may be suppied in '...' arguments as an alternative to the 'outcomes' argument"))
        }
        rv$outcomes <- unlist(simset.args[!arg.is.simset])
    }
    if (!is.character(rv$outcomes) || is.null(rv$outcomes) || any(is.na(rv$outcomes)) || any(duplicated(rv$outcomes))) {
        if (sum(!arg.is.simset) > 0) {
            stop(paste0(error.prefix, "'outcomes' found as unnamed argument in '...' must be a character vector with no NAs or duplicates"))
        } else {
            stop(paste0(error.prefix, "'outcomes' must be a character vector with no NAs or duplicates"))
        }
    }

    if (sum(arg.is.simset) < 1) {
        stop(paste0(error.prefix, "one or more jheem.simulation.set objects must be supplied"))
    }
    # browser()
    # Add names to simsets
    rv$simset.list <- setNames(simset.args[arg.is.simset], deparsed.substituted.args.simset.args[arg.is.simset])
    if (is.null(names(simset.args))) {
        simset.explicitly.named <- rep(F, sum(arg.is.simset))
    } else {
        simset.explicitly.named <- sapply(names(simset.args[arg.is.simset]), function(name) {
            nchar(name) > 0
        })
    }
    names(rv$simset.list)[simset.explicitly.named] <- names(simset.args)[simset.explicitly.named]

    # - make sure they are all the same version and the location
    if (length(unique(sapply(rv$simset.list, function(simset) {
        simset$version
    }))) > 1) {
        stop(paste0(error.prefix, "all simulation sets must have the same version"))
    }
    if (length(unique(sapply(rv$simset.list, function(simset) {
        simset$location
    }))) > 1) {
        stop(paste0(error.prefix, "all simulation sets must have the same location"))
    }

    # Check outcomes
    # - make sure each outcome is present in sim$outcomes for at least one sim/simset
    if (any(sapply(rv$outcomes, function(outcome) {
        !any(sapply(rv$simset.list, function(simset) {
            outcome %in% simset$outcomes
        }))
    }))) {
        stop(paste0("There weren't any simulation sets for one or more outcomes. Should this be an error?"))
    }

    return(rv)
}


#' @title Simplot Data Only
#' @inheritParams simplot
#' @param A character vector of which simulation outcomes to plot. Note: This should be the names of the outcomes in the provided data manager, NOT in the simulations.
#' @param title NULL or a single, non-NA character value. If "location", the first location provided in "locations" will be used for the title.
#' @export
simplot.data.only <- function(outcomes,
                              locations,
                              split.by = NULL,
                              facet.by = NULL,
                              dimension.values = list(),
                              target.ontology = NULL,
                              plot.year.lag.ratio = F,
                              title = "location",
                              n.facet.rows = NULL,
                              append.url = F,
                              data.manager = get.default.data.manager(),
                              style.manager = get.default.style.manager(),
                              show.data.pull.error = F,
                              debug = F) {
    error.prefix <- "Cannot generate simplot: "

    # @ validate locations

    prepared.plot.data <- prepare.plot( # Should this be prepare_plot_local? Assuming original was prepare.plot
        simset.list = NULL,
        outcomes = outcomes,
        locations = locations,
        corresponding.data.outcomes = corresponding.data.outcomes, # This variable is not defined in this scope, might be a bug in original
        split.by = split.by,
        facet.by = facet.by,
        dimension.values = dimension.values,
        target.ontology = target.ontology,
        plot.which = "data.only",
        summary.type = summary.type, # This variable is not defined in this scope, might be a bug in original
        plot.year.lag.ratio = plot.year.lag.ratio,
        title = title,
        append.url = append.url,
        data.manager = data.manager,
        style.manager = style.manager,
        show.data.pull.error = show.data.pull.error,
        debug = debug
    )
    execute.simplot(prepared.plot.data, # Should this be execute_simplot_local?
        outcomes = outcomes,
        split.by = split.by,
        facet.by = facet.by,
        plot.which = plot.which, # This variable is not defined in this scope, might be a bug in original
        summary.type = summary.type, # This variable is not defined in this scope, might be a bug in original
        plot.year.lag.ratio = plot.year.lag.ratio,
        n.facet.rows = n.facet.rows,
        style.manager = style.manager,
        debug = debug
    )
}

#' Prepare Plot Data
#' A utility that performs the data-pulling half of the simplot operation
#' for applications like webtools that need the step to be separate.
#' @inheritParams simplot
#' @param simset.list A list of jheem.simulation.set objects
#' @param plot.which Should simulation data and calibration data be plotted ('sim.and.data'), or only simulation data ('sim.only'), or only calibration data ('data.only')
#' @value A list with three components:
#' df.sim, a data frame containing simulation data (may be NULL)
#' df.truth, a data frame containing calibration data (may be NULL)
#' details, a list with components "y.label", "plot.title", "outcome.metadata.list", "source.metadata.list", and "sim.labels.list"
#' @export
prepare_plot_local <- function(simset.list = NULL,
                               outcomes = NULL,
                               locations = NULL,
                               corresponding.data.outcomes = NULL,
                               split.by = NULL,
                               facet.by = NULL,
                               dimension.values = list(),
                               target.ontology = NULL,
                               plot.which = c("sim.and.data", "sim.only", "data.only")[1],
                               summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                               plot.year.lag.ratio = F,
                               title = "location",
                               append.url = F,
                               data.manager = get.default.data.manager(),
                               style.manager = get.default.style.manager(),
                               show.data.pull.error = F,
                               debug = F) {
    #-- VALIDATION ----
    if (debug) browser()
    error.prefix <- "Cannot generate simplot: "

    if (!R6::is.R6(data.manager) || !is(data.manager, "jheem.data.manager")) {
        stop("'data.manager' must be an R6 object with class 'jheem.data.manager'")
    }

    # *split.by* is NULL or a single, non-NA character vector
    if (!is.null(split.by) && (!is.character(split.by) || length(split.by) > 1 || is.na(split.by))) {
        stop(paste0(error.prefix, "'split.by' must be NULL or a length one, non-NA character vector"))
    }

    # *facet.by* is NULL or a character vector of length > 0 with no NAs or duplicates
    if (!is.null(facet.by) && (!is.character(facet.by) || length(facet.by) < 1 || any(is.na(facet.by)) || any(duplicated(facet.by)))) {
        stop(paste0(error.prefix, "'facet.by' must be NULL or a character vector with at least one element and no NAs or duplicates"))
    }

    if (!is.null(split.by) && split.by %in% facet.by) {
        stop(paste0(error.prefix, "'facet.by' must not contain the dimension in 'split.by'"))
    }

    if (!is.null(split.by) && split.by == "year") {
        stop(paste0(error.prefix, "'split.by' cannot equal 'year'"))
    }

    if (!is.null(facet.by) && "year" %in% facet.by) {
        stop(paste0(error.prefix, "'facet.by' cannot contain 'year'"))
    }

    if (!is.null(target.ontology) &&
        !is.ontology(target.ontology) &&
        !(is.list(target.ontology) && all(sapply(target.ontology, function(x) {
            is.ontology((x))
        })) && !is.null(names(target.ontology)))) {
        stop(paste0(error.prefix, "'target.ontology' must be NULL, an ontology, or a list of ontologies with outcomes as names"))
    }

    if (!identical(plot.year.lag.ratio, T) && !identical(plot.year.lag.ratio, F)) {
        stop(paste0(error.prefix, "'plot.year.lag.ratio' must be either T or F"))
    }

    if (plot.year.lag.ratio && length(outcomes) > 1) {
        stop(paste0(error.prefix, "only one outcome can be used with 'plot.year.lag.ratio'"))
    }

    if (!is.null(title) && (!is.character(title) || length(title) != 1 || is.na(title))) {
        stop(paste0(error.prefix, "'title' must be NULL or a single, non-NA character value"))
    }

    if (!identical(append.url, T) && !identical(append.url, F)) {
        stop(paste0(error.prefix, "'append.url' must be either T or F"))
    }

    if (!identical(show.data.pull.error, T) && !identical(show.data.pull.error, F)) {
        stop(paste0(error.prefix, "'show.data.pull.error' must be either T or F"))
    }

    #-- GET OUTCOME METADATA ----
    if (plot.which == "data.only") {
        outcome.metadata.list <- lapply(outcomes, function(outcome) {
            data.manager$outcome.info[[outcome]]$metadata
        })
    } else {
        outcome.metadata.list <- lapply(outcomes, function(outcome) {
            idx <- 1 # Use idx to avoid conflict with outer loop variable i if this function is nested
            while (idx <= length(simset.list)) {
                if (outcome %in% names(simset.list[[idx]]$outcome.metadata)) {
                    return(simset.list[[idx]]$outcome.metadata[[outcome]])
                } else {
                    idx <- idx + 1
                }
            }
            stop(paste0(error.prefix, "Metadata not found for outcome '", outcome, "' in any provided simset."))
        })
    }
    names(outcome.metadata.list) <- outcomes

    # Determine corresponding data outcomes
    if (plot.which == "data.only") {
        outcomes.for.data <- setNames(outcomes, outcomes)
    } else {
        outcomes.for.data <- sapply(outcomes, function(outcome_val) {
            if (outcome_val %in% names(corresponding.data.outcomes)) {
                return(corresponding.data.outcomes[[outcome_val]])
            }
            co_outcome <- NULL
            j <- 1
            while (j <= length(simset.list)) {
                if (outcome_val %in% names(simset.list[[j]]$outcome.metadata)) {
                    co_outcome <- simset.list[[j]]$outcome.metadata[[outcome_val]]$corresponding.observed.outcome
                    break
                } else {
                    j <- j + 1
                }
            }
            co_outcome
        })
    }

    if (plot.which == "data.only") {
        outcome.ontologies <- NULL
    } else {
        # Match package logic: outcome.ontologies are derived *only* from simset.list.
        # The target.ontology function argument is used later in pull/get decisions for the 'to.ontology' part of a mapping.
        outcome.ontologies <- lapply(outcomes, function(outcome) {
            outcome.ontology.val <- NULL
            idx <- 1
            while (idx <= length(simset.list)) {
                # Check if simset.list[[idx]]$outcome.ontologies itself is not NULL
                if (!is.null(simset.list[[idx]]$outcome.ontologies) &&
                    outcome %in% names(simset.list[[idx]]$outcome.ontologies)) {
                    outcome.ontology.val <- simset.list[[idx]]$outcome.ontologies[[outcome]]
                    break
                } else {
                    idx <- idx + 1
                }
            }
            # Package version stops if not found. Replicating this.
            # This ensures that if an outcome is expected to have an ontology defined in the simset, it must be present.
            if (is.null(outcome.ontology.val)) {
                stop(paste0(
                    error.prefix, "No entry in any simset$outcome.ontologies for outcome '", outcome,
                    "'. This is required when plot.which is not 'data.only'."
                ))
            }
            outcome.ontology.val
        })
        names(outcome.ontologies) <- outcomes # Ensure the list is named by outcome
    }

    if (plot.which == "data.only") {
        outcome.locations <- locations
    } else {
        outcome.locations <- lapply(outcomes, function(outcome) {
            unique(unlist(lapply(simset.list, function(simset) {
                simset$outcome.location.mapping$get.observed.locations(outcome, simset$location)
            })))
        })
        names(outcome.locations) <- outcomes.for.data # names should align with data being pulled
    }

    if (plot.which != "data.only") {
        sim.labels.list <- lapply(simset.list, function(simset) {
            simset$metadata$labels
        })
    } else {
        sim.labels.list <- NULL
    }

    #-- MAKE A DATA FRAME WITH ALL THE REAL-WORLD DATA ----
    outcome.mappings <- list()
    source.metadata.list <- list()
    # append.attributes will be determined inside the loop using the helper function
    df.truth <- NULL
    for (i in seq_along(outcomes.for.data)) {
        current_data_outcome_name_for_pull <- outcomes.for.data[[i]] # Define this early for use below

        if (plot.which != "sim.only" && !is.null(current_data_outcome_name_for_pull)) {
            # Determine initial attributes based on append.url flag
            initial_append_attrs <- if (isTRUE(append.url)) "url" else NULL

            # --- Start: Logic to determine pull arguments (ontology, allow_mapping) ---
            # (Using the logic reverted to match package behavior)
            current_sim_outcome_name <- names(outcomes.for.data)[i]
            pull_target_ontology <- NULL
            pull_allow_mapping <- NA # Use NA to detect if default should be used

            if (!is.null(target.ontology) && !is.list(target.ontology)) {
                pull_target_ontology <- target.ontology
                pull_allow_mapping <- FALSE
            } else if (is.list(target.ontology) && current_data_outcome_name_for_pull %in% names(target.ontology)) {
                pull_target_ontology <- target.ontology[[current_data_outcome_name_for_pull]]
                pull_allow_mapping <- FALSE
            } else if (plot.which == "sim.and.data" && !is.null(outcome.ontologies[[current_sim_outcome_name]])) {
                pull_target_ontology <- outcome.ontologies[[current_sim_outcome_name]]
                pull_allow_mapping <- TRUE
            } else {
                pull_target_ontology <- NULL
                # pull_allow_mapping remains NA, default used by pull()
            }
            # --- End: Logic to determine pull arguments ---

            # --- Start: Construct base arguments list (without append.attributes initially) ---
            base_pull_args <- list(
                outcome = current_data_outcome_name_for_pull,
                dimension.values = c(dimension.values, list(location = outcome.locations[[current_data_outcome_name_for_pull]])),
                keep.dimensions = c("year", "location", facet.by, split.by),
                target.ontology = pull_target_ontology,
                na.rm = T,
                debug = F
            )
            if (!is.na(pull_allow_mapping)) {
                base_pull_args$allow.mapping.from.target.ontology <- pull_allow_mapping
            }
            # --- End: Construct base arguments list ---

            # --- Start: Try-Retry Logic for data pull ---
            outcome.data <- tryCatch(
                {
                    # Attempt 1: Pull with initial append.attributes
                    attempt1_args <- base_pull_args
                    attempt1_args$append.attributes <- initial_append_attrs
                    
                    # DEBUG: Log the exact parameters being passed
                    cat("=== DEBUG: CONTAINER DATA MANAGER PULL ===\n")
                    cat("Outcome:", current_data_outcome_name_for_pull, "\n")
                    cat("Append attributes:", initial_append_attrs, "\n")
                    cat("Target ontology:", if(is.null(attempt1_args$target.ontology)) "NULL" else "PROVIDED", "\n")
                    if(!is.null(attempt1_args$target.ontology)) {
                        cat("Target ontology sex:", attempt1_args$target.ontology$sex, "\n")
                    }
                    cat("Allow mapping:", attempt1_args$allow.mapping.from.target.ontology, "\n")
                    cat("=== END DEBUG ===\n")
                    
                    cat("=== FIRST ATTEMPT (with URLs) ===\n")
                    result <- tryCatch({
                        do.call(data.manager$pull, attempt1_args)
                    }, error = function(e) {
                        cat("=== FIRST ATTEMPT FAILED ===\n")
                        cat("Error message:", e$message, "\n")
                        cat("Error class:", class(e), "\n")
                        # Re-throw the error to maintain normal flow
                        stop(e)
                    })
                    cat("=== FIRST ATTEMPT SUCCEEDED ===\n")
                    
                    result
                },
                error = function(e) {
                    # Check if the failure might be due to appending URL
                    if (!is.null(initial_append_attrs) && initial_append_attrs == "url") {
                        warning(paste(
                            "Could not pull data for outcome '", current_data_outcome_name_for_pull,
                            "' with URL attribute attached. Retrying without URL attribute. Original error:", e$message
                        ))
                        # Attempt 2: Retry pull with append.attributes = NULL
                        retry_args <- base_pull_args
                        retry_args$append.attributes <- NULL
                        cat("=== RETRY ATTEMPT (without URLs) ===\n")
                        outcome.data.retry <- tryCatch(
                            {
                                result_retry <- do.call(data.manager$pull, retry_args)
                                cat("=== RETRY ATTEMPT SUCCEEDED ===\n")
                                if (!is.null(result_retry)) {
                                    cat("Retry result sex dimensions:", paste(dimnames(result_retry)$sex, collapse=", "), "\n")
                                }
                                result_retry
                            },
                            error = function(e_retry) {
                                cat("=== RETRY ATTEMPT FAILED ===\n")
                                cat("Retry error:", e_retry$message, "\n")
                                # If retry also fails, handle based on show.data.pull.error
                                if (show.data.pull.error) {
                                    stop(paste0(error.prefix, "Retry failed for '", current_data_outcome_name_for_pull, "': ", e_retry$message))
                                } else {
                                    return(NULL)
                                } # Return NULL if retry fails and errors are hidden
                            }
                        )
                        return(outcome.data.retry) # Return result of retry (could be data or NULL)
                    } else {
                        # Original error was not related to appending URL, handle as before
                        if (show.data.pull.error) {
                            stop(paste0(error.prefix, e$message))
                        } else {
                            return(NULL)
                        } # Return NULL if errors are hidden
                    }
                }
            )
            # --- End: Try-Retry Logic ---

            # --- Start: Process outcome.data (if not NULL) ---
            if (!is.null(attr(outcome.data, "mapping"))) {
                outcome.mappings <- c(outcome.mappings, list(attr(outcome.data, "mapping")))
            } else {
                outcome.mappings <- c(outcome.mappings, list(NULL))
            }

            if (!is.null(outcome.data)) {
                if (data.manager$outcome.info[[outcomes.for.data[[i]]]]$metadata$display.as.percent) {
                    outcome.data <- outcome.data * 100
                }
                one.df.outcome <- reshape2::melt(outcome.data, na.rm = T, as.is = T)

                # Use isTRUE() to handle potential NA in append.url
                if (isTRUE(append.url)) {
                    one.df.outcome$data_url <- NA_character_
                    url_attribute <- attr(outcome.data, "url")

                    if (!is.null(url_attribute)) {
                        melt_error_message <- NULL
                        melted_url_data <- "MELT_NOT_RUN_OR_FAILED_PRE_ASSIGN"

                        melted_url_data <- tryCatch(
                            reshape2::melt(url_attribute, na.rm = T, as.is = T),
                            error = function(e) {
                                melt_error_message <<- paste("Error during melt of url_attribute:", e$message)
                                NULL
                            }
                        )

                        # --- Start Debug Block for melt result ---
                        print(paste("--- Debugging melt for outcome:", outcomes.for.data[[i]], "---"))
                        if (!is.null(melt_error_message)) {
                            print(melt_error_message)
                        }
                        print("Value/structure of melted_url_data after tryCatch:")
                        if (identical(melted_url_data, "MELT_NOT_RUN_OR_FAILED_PRE_ASSIGN")) {
                            print("Melt was not attempted or tryCatch block had an issue before assignment to melted_url_data.")
                        } else if (is.null(melted_url_data)) {
                            print("melted_url_data is NULL (melt likely failed and error handler returned NULL).")
                        } else {
                            print("melted_url_data is not NULL. Structure:")
                            str(melted_url_data)
                        }
                        # To inspect further if needed, uncomment the browser() call below
                        # browser()
                        # --- End Debug Block ---

                        if (!is.null(melted_url_data) && inherits(melted_url_data, "data.frame") && "value" %in% names(melted_url_data)) {
                            if (nrow(one.df.outcome) == nrow(melted_url_data)) {
                                one.df.outcome$data_url <- as.character(melted_url_data$value)
                            } else {
                                warning(paste("Row mismatch (melted URL vs outcome) for:", outcomes.for.data[[i]], ". URLs may be misaligned. Melted URL rows:", nrow(melted_url_data), "Outcome rows:", nrow(one.df.outcome)))
                            }
                        } else if (is.list(url_attribute) && (is.null(dim(url_attribute)) || length(dim(url_attribute)) == 1)) {
                            url_vector <- unlist(url_attribute)
                            if (length(url_vector) == nrow(one.df.outcome)) {
                                one.df.outcome$data_url <- as.character(url_vector)
                            } else {
                                warning(paste("Length mismatch (unlisted URL attribute vs outcome rows) for:", outcomes.for.data[[i]], ". Length URL:", length(url_vector), "Length Df:", nrow(one.df.outcome)))
                            }
                        } else {
                            if (is.null(melt_error_message) && !identical(melted_url_data, "MELT_NOT_RUN_OR_FAILED_PRE_ASSIGN") && !is.null(melted_url_data)) {
                                warning(paste("URL attribute for", outcomes.for.data[[i]], "has an unexpected structure or melt failed to produce 'value' column. data_url remains NA."))
                            }
                        }
                    }
                }

                if (!any(sapply(one.df.outcome$year, is.year.range))) {
                    one.df.outcome$year <- as.numeric(one.df.outcome$year)
                } else if (plot.year.lag.ratio) {
                    stop(paste0(error.prefix, "cannot use 'plot.year.lag.ratio' when data is in year ranges"))
                }

                sources.this.outcome <- unique(one.df.outcome$source)
                source.metadata.list <- c(source.metadata.list, data.manager$source.info[setdiff(sources.this.outcome, names(source.metadata.list))])

                corresponding_outcome_name <- names(outcomes.for.data)[i] # Get the original outcome name
                one.df.outcome["outcome"] <- corresponding_outcome_name
                one.df.outcome["outcome.display.name"] <- outcome.metadata.list[[corresponding_outcome_name]]$display.name

                # Ensure column consistency before rbind
                if (!is.null(df.truth) && nrow(df.truth) > 0) {
                    missing_cols_in_new <- setdiff(names(df.truth), names(one.df.outcome))
                    if (length(missing_cols_in_new) > 0) {
                        one.df.outcome[missing_cols_in_new] <- NA
                    }
                    missing_cols_in_main <- setdiff(names(one.df.outcome), names(df.truth))
                    if (length(missing_cols_in_main) > 0) {
                        df.truth[missing_cols_in_main] <- NA
                    }
                    one.df.outcome <- one.df.outcome[, names(df.truth), drop = FALSE] # Reorder
                }
                df.truth <- rbind(df.truth, one.df.outcome)
            }
        } else {
            outcome.mappings <- c(outcome.mappings, list(NULL))
        }
    }

    if (!is.null(df.truth) && nrow(df.truth) > 0) {
        if (!is.null(split.by) && split.by %in% names(df.truth)) names(df.truth)[names(df.truth) == split.by] <- "stratum"
        if (!is.null(facet.by)) {
            for (j in seq_along(facet.by)) { # Use j to avoid conflict
                if (facet.by[j] %in% names(df.truth)) names(df.truth)[names(df.truth) == facet.by[j]] <- paste0("facet.by", j)
            }
        }
        if (!("stratum" %in% names(df.truth))) df.truth["stratum"] <- ""
        if ("stratum" %in% names(df.truth)) df.truth <- df.truth[order(df.truth$stratum), ]
    }
    names(outcome.mappings) <- outcomes # This should use original outcome names

    #-- MAKE A DATA FRAME WITH THE SIMULATION DATA ----
    df.sim <- NULL
    if (plot.which != "data.only") {
        for (outcome_val_sim in outcomes) { # Use outcome_val_sim
            keep.dimensions <- c("year", facet.by, split.by)
            for (k in seq_along(simset.list)) { # Use k
                simset <- simset.list[[k]]
                mapping.this.outcome <- NULL
                if (!is.null(outcome.mappings[[outcome_val_sim]])) {
                    mapping.this.outcome <- outcome.mappings[[outcome_val_sim]]
                } else if (is.list(target.ontology) && outcome_val_sim %in% names(target.ontology)) { # Check if outcome_val_sim is in target.ontology list
                    mapping.this.outcome <- get.ontology.mapping(outcome.ontologies[[outcome_val_sim]], target.ontology[[outcome_val_sim]])
                } else if (!is.null(target.ontology) && !is.list(target.ontology)) { # Check if target.ontology is a single ontology
                    mapping.this.outcome <- get.ontology.mapping(outcome.ontologies[[outcome_val_sim]], target.ontology)
                }

                simset.data.this.outcome <- simset$get(
                    outcomes = outcome_val_sim,
                    dimension.values = dimension.values,
                    keep.dimensions = keep.dimensions,
                    drop.single.outcome.dimension = T,
                    mapping = mapping.this.outcome,
                    summary.type = summary.type
                )

                if (is.null(simset.data.this.outcome)) next

                if (simset.list[[k]][["outcome.metadata"]][[outcome_val_sim]]$display.as.percent) {
                    simset.data.this.outcome <- simset.data.this.outcome * 100
                }

                one.df.sim.this.outcome <- reshape2::melt(simset.data.this.outcome, na.rm = T)
                one.df.sim.this.outcome <- as.data.frame(lapply(one.df.sim.this.outcome, function(col) {
                    if (is.factor(col)) {
                        as.character(col)
                    } else {
                        col
                    }
                }))

                one.df.sim.this.outcome["simset"] <- names(simset.list)[[k]]
                one.df.sim.this.outcome["outcome"] <- outcome_val_sim
                one.df.sim.this.outcome["linewidth"] <- 1 / (style.manager$linewidth.slope * log10(simset$n.sim) + 1)
                one.df.sim.this.outcome["alpha"] <- one.df.sim.this.outcome["linewidth"]
                one.df.sim.this.outcome["outcome.display.name"] <- outcome.metadata.list[[outcome_val_sim]]$display.name

                # Ensure column consistency before rbind for df.sim
                if (!is.null(df.sim) && nrow(df.sim) > 0) {
                    missing_cols_in_new <- setdiff(names(df.sim), names(one.df.sim.this.outcome))
                    if (length(missing_cols_in_new) > 0) {
                        one.df.sim.this.outcome[missing_cols_in_new] <- NA
                    }
                    missing_cols_in_main <- setdiff(names(one.df.sim.this.outcome), names(df.sim))
                    if (length(missing_cols_in_main) > 0) {
                        df.sim[missing_cols_in_main] <- NA
                    }
                    one.df.sim.this.outcome <- one.df.sim.this.outcome[, names(df.sim), drop = FALSE] # Reorder
                }
                df.sim <- rbind(df.sim, one.df.sim.this.outcome)
            }
        }

        if (summary.type != "individual.simulation" && !is.null(df.sim) && nrow(df.sim) > 0) {
            # Ensure 'metric' and 'value' columns exist before reshape
            if ("metric" %in% names(df.sim) && "value" %in% names(df.sim)) {
                id_vars <- names(df.sim)[!(names(df.sim) %in% c("metric", "value"))]
                # Ensure id_vars are not empty and exist in df.sim
                id_vars <- intersect(id_vars, names(df.sim))
                if (length(id_vars) > 0) {
                    df.sim <- reshape(df.sim, direction = "wide", idvar = id_vars, timevar = "metric")
                } else {
                    warning("Not enough identifying variables for reshape (wide) of df.sim.")
                }
            } else {
                warning("Missing 'metric' or 'value' column in df.sim for summary type, skipping reshape.")
            }
            if (!is.null(df.sim[["value.mean"]])) df.sim$value <- df.sim$value.mean
            if (!is.null(df.sim[["value.median"]])) df.sim$value <- df.sim$value.median
        }

        if (!is.null(df.sim) && nrow(df.sim) > 0) {
            if (!is.null(split.by) && split.by %in% names(df.sim)) df.sim["stratum"] <- df.sim[split.by]
            if (!is.null(facet.by)) {
                for (j in seq_along(facet.by)) { # Use j
                    if (facet.by[j] %in% names(df.sim)) df.sim[paste0("facet.by", j)] <- df.sim[facet.by[j]]
                }
            }
            if (!("stratum" %in% names(df.sim))) df.sim["stratum"] <- ""
            if ("simset" %in% names(df.sim)) df.sim$simset <- factor(df.sim$simset)
            if ("sim" %in% names(df.sim)) df.sim$sim <- factor(df.sim$sim)

            # Construct groupid correctly for each row
            df.sim$groupid <- paste(
                df.sim$outcome %||% "NA_o",
                df.sim$simset %||% "NA_ss",
                df.sim$sim %||% "NA_s",
                df.sim$stratum %||% "NA_st",
                sep = "_"
            )

            if ("stratum" %in% names(df.sim)) df.sim <- df.sim[order(df.sim$stratum), ]
        }
    }

    #-- YEAR LAG RATIO #----
    if (plot.year.lag.ratio) {
        if (!is.null(df.truth) && nrow(df.truth) > 0) {
            df.truth$value <- log(df.truth$value)
            # Combine facet.by and split.by into stratum for lag calculation
            temp_stratum_truth <- rep("", nrow(df.truth))
            if (!is.null(split.by) && "stratum" %in% names(df.truth)) temp_stratum_truth <- df.truth$stratum

            facet_components_truth <- character()
            if (!is.null(facet.by)) {
                for (k_facet in seq_along(facet.by)) { # Use k_facet
                    col_name <- paste0("facet.by", k_facet)
                    if (col_name %in% names(df.truth)) facet_components_truth <- cbind(facet_components_truth, df.truth[[col_name]])
                }
            }
            if (ncol(facet_components_truth) > 0) temp_stratum_truth <- paste(temp_stratum_truth, apply(facet_components_truth, 1, paste, collapse = "_"), sep = "_")

            df.truth[["temp_lag_stratum"]] <- temp_stratum_truth

            truth.lag.indices <- generate_lag_matrix_indices(
                as.integer(as.factor(df.truth$year)),
                as.integer(as.factor(df.truth$location)),
                as.integer(as.factor(df.truth$temp_lag_stratum)),
                as.integer(as.factor(df.truth$source)),
                nrow(df.truth)
            )
            truth.n.lag.pairs <- length(truth.lag.indices) / 2

            if (truth.n.lag.pairs > 0) {
                truth.lag.values <- apply_lag_to_vector(df.truth$value, truth.lag.indices, rep(0, truth.n.lag.pairs), truth.n.lag.pairs)
                truth.rows.to.keep <- truth.lag.indices[rep(c(T, F), truth.n.lag.pairs)] + 1
                df.truth <- df.truth[truth.rows.to.keep, ]
                df.truth$value <- exp(truth.lag.values)
                df.truth <- df.truth[!is.na(df.truth$value) & !is.infinite(df.truth$value), ]
            } else {
                df.truth <- df.truth[0, ] # Empty if no pairs
            }
            df.truth$temp_lag_stratum <- NULL # remove helper
            if (nrow(df.truth) == 0) df.truth <- NULL
        }
        if (!is.null(df.sim) && nrow(df.sim) > 0) {
            df.sim$value <- log(df.sim$value)
            if (!is.null(df.sim$value.lower) && !is.null(df.sim$value.upper)) {
                df.sim$value.lower <- log(df.sim$value.lower)
                df.sim$value.upper <- log(df.sim$value.upper)
            }

            temp_stratum_sim <- rep("", nrow(df.sim))
            if (!is.null(split.by) && "stratum" %in% names(df.sim)) temp_stratum_sim <- df.sim$stratum

            facet_components_sim <- character()
            if (!is.null(facet.by)) {
                for (k_facet_sim in seq_along(facet.by)) {
                    col_name_sim <- paste0("facet.by", k_facet_sim)
                    if (col_name_sim %in% names(df.sim)) facet_components_sim <- cbind(facet_components_sim, df.sim[[col_name_sim]])
                }
            }
            if (ncol(facet_components_sim) > 0) temp_stratum_sim <- paste(temp_stratum_sim, apply(facet_components_sim, 1, paste, collapse = "_"), sep = "_")
            df.sim[["temp_lag_stratum"]] <- temp_stratum_sim

            sim.lag.indices <- generate_lag_matrix_indices(
                as.integer(as.factor(df.sim$year)),
                as.integer(as.factor(df.sim$sim)),
                as.integer(as.factor(df.sim$temp_lag_stratum)),
                as.integer(as.factor(df.sim$simset)),
                nrow(df.sim)
            )
            sim.n.lag.pairs <- length(sim.lag.indices) / 2

            if (sim.n.lag.pairs > 0) {
                sim.lag.values <- apply_lag_to_vector(df.sim$value, sim.lag.indices, rep(0, sim.n.lag.pairs), sim.n.lag.pairs)
                sim.rows.to.keep <- sim.lag.indices[rep(c(T, F), sim.n.lag.pairs)] + 1

                if (!is.null(df.sim$value.lower) && !is.null(df.sim$value.upper)) {
                    sim.lower.lag.values <- apply_lag_to_vector(df.sim$value.lower, sim.lag.indices, rep(0, sim.n.lag.pairs), sim.n.lag.pairs)
                    sim.upper.lag.values <- apply_lag_to_vector(df.sim$value.upper, sim.lag.indices, rep(0, sim.n.lag.pairs), sim.n.lag.pairs)
                }
                df.sim <- df.sim[sim.rows.to.keep, ]
                df.sim$value <- exp(sim.lag.values)
                if (!is.null(df.sim$value.lower) && !is.null(df.sim$value.upper)) {
                    df.sim$value.lower <- exp(sim.lower.lag.values)
                    df.sim$value.upper <- exp(sim.upper.lag.values)
                }
                df.sim <- df.sim[!is.na(df.sim$value) & !is.infinite(df.sim$value), ]
            } else {
                df.sim <- df.sim[0, ] # Empty if no pairs
            }
            df.sim$temp_lag_stratum <- NULL # remove helper
            if (nrow(df.sim) == 0) df.sim <- NULL
        }
    }

    #-- PACKAGE AND RETURN ----
    if (plot.which == "data.only") {
        y.label_val <- sapply(outcomes, function(outcome) {
            data.manager$outcome.info[[outcome]]$metadata$units
        })
    } else {
        y.label_val <- paste0(sapply(outcomes, function(outcome) {
            simset.list[[1]][["outcome.metadata"]][[outcome]][["units"]]
        }), collapse = "/")
    }
    if (plot.year.lag.ratio) {
        y.label_val <- paste0("Log difference in ", y.label_val)
    }

    plot.title_val <- title # Default
    if (title == "location") {
        if (plot.which == "data.only" && !is.null(locations) && length(locations) > 0) {
            plot.title_val <- paste0(get.location.name(locations[[1]]), " (", locations[[1]], ")")
        } else if (!is.null(simset.list) && length(simset.list) > 0) {
            plot.title_val <- paste0(get.location.name(simset.list[[1]]$location), " (", simset.list[[1]]$location, ")")
        }
    }

    return(list(
        df.sim = df.sim,
        df.truth = df.truth,
        details = list(
            y.label = y.label_val,
            plot.title = plot.title_val,
            outcome.metadata.list = outcome.metadata.list,
            source.metadata.list = source.metadata.list,
            sim.labels.list = sim.labels.list
        )
    ))
}

execute_simplot_local <- function(prepared.plot.data,
                                  outcomes = NULL,
                                  split.by = NULL,
                                  facet.by = NULL,
                                  plot.which = c("sim.and.data", "sim.only", "data.only")[1],
                                  summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                                  plot.year.lag.ratio = F,
                                  n.facet.rows = NULL,
                                  style.manager = get.default.style.manager(),
                                  facet_labeller = NULL, # NEW: Optional labeller function
                                  debug = F) {
    if (debug) browser()
    #-- UNPACK DATA --#
    df.sim <- prepared.plot.data$df.sim
    df.truth <- prepared.plot.data$df.truth
    y.label <- prepared.plot.data$details$y.label
    plot.title <- prepared.plot.data$details$plot.title

    #-- PREPARE PLOT COLORS, SHADES, SHAPES, ETC. --#
    if (!is.null(df.sim)) {
        # Fully reverted to original package logic for direct assignment
        # This assumes df.sim contains columns named by style.manager$xxx.sim.by values (e.g., "simset")
        # and that these source columns exist.
        df.sim["linetype.sim.by"] <- df.sim[[style.manager$linetype.sim.by]]
        df.sim["shape.sim.by"] <- df.sim[[style.manager$shape.sim.by]]
        df.sim["color.sim.by"] <- df.sim[[style.manager$color.sim.by]]
        if (!is.null(df.sim) && "color.sim.by" %in% names(df.sim) && is.factor(df.sim$color.sim.by)) {
            df.sim$color.sim.by <- as.character(df.sim$color.sim.by)
        }
    }

    if (!is.null(df.sim) && nrow(df.sim) > 0) {
        has_ci_cols <- all(c("value.lower", "value.upper") %in% names(df.sim))
        plot_summary <- summary.type != "individual.simulation"
        df.sim$ci_hover_text <- sapply(1:nrow(df.sim), function(j) {
            current_year <- df.sim$year[j]
            year_fmt <- if (is.numeric(current_year) && !is.na(current_year)) {
                if (current_year == floor(current_year)) sprintf("%d", current_year) else sprintf("%.1f", current_year)
            } else {
                sprintf("%s", as.character(current_year))
            }
            current_value <- if ("value" %in% names(df.sim)) df.sim$value[j] else NA
            base_text <- sprintf("Year: %s\nValue: %.2f", year_fmt, round(current_value, 2))
            ci_text <- ""
            if (plot_summary && has_ci_cols) {
                lower_ci <- df.sim$value.lower[j]
                upper_ci <- df.sim$value.upper[j]
                if (!is.na(lower_ci) && !is.na(upper_ci)) {
                    ci_text <- sprintf("\nLower CI: %.2f\nUpper CI: %.2f", round(lower_ci, 2), round(upper_ci, 2))
                }
            }
            paste0(base_text, ci_text)
        })
    }

    if (!is.null(df.truth)) {
        # make some other columns (Original Package Logic)
        # This assumes 'location' and columns named by style.manager$xxx.data.by exist in df.truth
        df.truth["location.type"] <- locations::get.location.type(df.truth$location)
        df.truth["shape.data.by"] <- df.truth[[style.manager$shape.data.by]]
        df.truth["color.data.by"] <- df.truth[[style.manager$color.data.by]]
        df.truth["shade.data.by"] <- df.truth[[style.manager$shade.data.by]]

        if (style.manager$color.data.by == "stratum" && !is.null(df.truth$stratum) && all(df.truth$stratum == "")) {
            df.truth["color.and.shade.data.by"] <- df.truth[["shade.data.by"]]
        } else if (style.manager$shade.data.by == "stratum" && !is.null(df.truth$stratum) && all(df.truth$stratum == "")) {
            df.truth["color.and.shade.data.by"] <- df.truth[["color.data.by"]]
        } else {
            # Original logic assumes 'shade.data.by' and 'color.data.by' columns were successfully created above for the paste
            df.truth["color.and.shade.data.by"] <- do.call(paste, c(df.truth[["shade.data.by"]], df.truth[["color.data.by"]], list(sep = "__")))
        }
    }

    colors.for.sim <- NULL
    color.data.primary.colors <- NULL
    sim.color.groups <- if (!is.null(df.sim) && "color.sim.by" %in% names(df.sim)) sort(unique(df.sim$color.sim.by)) else character(0)
    data.color.groups <- if (!is.null(df.truth) && "color.data.by" %in% names(df.truth)) sort(unique(df.truth$color.data.by)) else character(0)

    if (style.manager$color.sim.by == style.manager$color.data.by) {
        all.color.groups <- sort(union(sim.color.groups, data.color.groups))
        if (length(all.color.groups) > 0) {
            all.colors <- if (!is.null(df.sim) && nrow(df.sim) > 0) style.manager$get.sim.colors(length(all.color.groups)) else if (!is.null(df.truth) && nrow(df.truth) > 0) style.manager$get.data.colors(length(all.color.groups)) else NULL
            if (!is.null(all.colors)) names(all.colors) <- all.color.groups
            colors.for.sim <- all.colors[sim.color.groups]
            color.data.primary.colors <- all.colors[data.color.groups]
        }
    } else {
        if (length(sim.color.groups) > 0) {
            colors.for.sim <- style.manager$get.sim.colors(length(sim.color.groups))
            names(colors.for.sim) <- sim.color.groups
        }
        if (length(data.color.groups) > 0) {
            color.data.primary.colors <- style.manager$get.data.colors(length(data.color.groups))
            names(color.data.primary.colors) <- data.color.groups
        }
    }

    color.ribbon.by <- NULL
    if (!is.null(df.sim) && nrow(df.sim) > 0 && !is.null(colors.for.sim) && length(colors.for.sim) > 0) { # Added checks
        color.ribbon.by <- ggplot2::alpha(colors.for.sim, style.manager$alpha.ribbon)
    }

    color.data.shaded.colors <- NULL
    if (!is.null(df.truth) && nrow(df.truth) > 0 && !is.null(color.data.primary.colors) && length(color.data.primary.colors) > 0) {
        unique_shades <- if ("shade.data.by" %in% names(df.truth)) unique(df.truth$shade.data.by) else ""
        color.data.shaded.colors <- unlist(lapply(color.data.primary.colors, function(prim.color) {
            style.manager$get.shades(base.color = prim.color, length(unique_shades))
        }))

        unique_colors_for_names <- if ("color.data.by" %in% names(df.truth)) unique(df.truth$color.data.by) else ""
        if (identical(unique_colors_for_names, "")) {
            if (length(color.data.shaded.colors) == length(unique_shades)) names(color.data.shaded.colors) <- unique_shades
        } else {
            # Ensure expand.grid inputs are not empty
            grid_df1 <- if (length(unique_shades) > 0) unique_shades else ""
            grid_df2 <- if (length(unique_colors_for_names) > 0) unique_colors_for_names else ""
            expanded_names <- do.call(paste, c(expand.grid(grid_df1, grid_df2), list(sep = "__")))
            if (length(color.data.shaded.colors) == length(expanded_names)) names(color.data.shaded.colors) <- expanded_names
        }
    }

    shapes.for.data <- NULL
    shapes.for.sim <- NULL
    if (!is.null(df.truth) && "shape.data.by" %in% names(df.truth)) {
        unique_shapes_data <- unique(df.truth$shape.data.by)
        if (length(unique_shapes_data) > 0) {
            shapes.for.data <- style.manager$get.shapes(length(unique_shapes_data))
            names(shapes.for.data) <- unique_shapes_data
        }
    }
    if (!is.null(df.sim) && "shape.sim.by" %in% names(df.sim)) {
        unique_shapes_sim <- unique(df.sim$shape.sim.by)
        if (length(unique_shapes_sim) > 0) {
            shapes.for.sim <- style.manager$get.shapes(length(unique_shapes_sim))
            names(shapes.for.sim) <- unique_shapes_sim
        }
    }
    all.shapes.for.scale <- c(shapes.for.data, shapes.for.sim)
    all.shapes.for.scale <- all.shapes.for.scale[!duplicated(names(all.shapes.for.scale))] # Ensure unique names

    linetypes.for.sim <- NULL
    if (!is.null(df.sim) && "linetype.sim.by" %in% names(df.sim)) {
        unique_linetypes <- unique(df.sim$linetype.sim.by)
        if (length(unique_linetypes) > 0) {
            linetypes.for.sim <- style.manager$get.linetypes(length(unique_linetypes))
            names(linetypes.for.sim) <- unique_linetypes
        }
    }

    df.sim.groupids.one.member <- NULL
    df.sim.groupids.many.members <- NULL
    if (!is.null(df.sim) && nrow(df.sim) > 0 && "groupid" %in% names(df.sim)) {
        groupids.with.one.member <- setdiff(unique(df.sim$groupid), df.sim$groupid[which(duplicated(df.sim$groupid))])
        df.sim$groupid_has_one_member <- df.sim$groupid %in% groupids.with.one.member
        df.sim.groupids.one.member <- subset(df.sim, groupid_has_one_member)
        df.sim.groupids.many.members <- subset(df.sim, !groupid_has_one_member)
    }

    rv <- ggplot2::ggplot()
    rv <- rv +
        ggplot2::labs(y = y.label) +
        ggplot2::ggtitle(plot.title) +
        ggplot2::scale_alpha(guide = "none")

    if (!plot.year.lag.ratio) {
        rv <- rv + ggplot2::scale_y_continuous(limits = c(0, NA), labels = scales::comma)
    } else {
        rv <- rv + ggplot2::scale_y_continuous(labels = scales::comma)
    }

    # SIM ELEMENTS

    if (!is.null(df.sim.groupids.many.members) && nrow(df.sim.groupids.many.members) > 0) {
        aes_map_line <- ggplot2::aes(x = year, y = value, group = groupid, text = ci_hover_text, alpha = alpha, linewidth = linewidth)
        if ("linetype.sim.by" %in% names(df.sim.groupids.many.members)) aes_map_line$linetype <- sym("linetype.sim.by")
        if ("color.sim.by" %in% names(df.sim.groupids.many.members) && (!is.null(split.by) || style.manager$color.sim.by == "simset")) aes_map_line$color <- sym("color.sim.by")

        rv <- rv + ggplot2::geom_line(data = df.sim.groupids.many.members, mapping = aes_map_line)
        if (!is.null(linetypes.for.sim) && length(linetypes.for.sim) > 0) rv <- rv + ggplot2::scale_linetype_manual(name = "sim linetype", values = linetypes.for.sim, breaks = names(linetypes.for.sim))
        if ("linewidth" %in% names(df.sim)) rv <- rv + ggplot2::scale_linewidth(NULL, range = c(min(df.sim$linewidth, na.rm = T), 1), guide = "none")
    }
    if (!is.null(df.sim.groupids.one.member) && nrow(df.sim.groupids.one.member) > 0) {
        aes_map_point_sim <- ggplot2::aes(x = year, y = value, text = ci_hover_text)
        if ("shape.sim.by" %in% names(df.sim.groupids.one.member)) aes_map_point_sim$shape <- sym("shape.sim.by")
        if ("color.sim.by" %in% names(df.sim.groupids.one.member)) aes_map_point_sim$fill <- sym("color.sim.by") # Points use fill for color with some shapes

        rv <- rv + ggplot2::geom_point(data = df.sim.groupids.one.member, mapping = aes_map_point_sim, size = 2, show.legend = F) # Fixed size
        if (!is.null(shapes.for.sim) && length(shapes.for.sim) > 0) rv <- rv + ggplot2::scale_shape_manual(name = "sim shape", values = shapes.for.sim)
    }
    if (!is.null(colors.for.sim) && length(colors.for.sim) > 0) {
        if (!is.null(split.by) || style.manager$color.sim.by == "simset") { # Add color scale if split or coloring by simset
            rv <- rv + ggplot2::scale_color_manual(name = "sim color", values = colors.for.sim)
            # rv <- rv + ggplot2::scale_fill_manual(name = "sim color", values = colors.for.sim, guide = "none") # Removed this line - let's see if color scale applies to fill or if ribbon needs its own fill scale added later
        }
    }



    # DATA ELEMENTS
    if (!is.null(df.truth) && nrow(df.truth) > 0) {
        if (!is.null(df.sim.groupids.one.member) && nrow(df.sim.groupids.one.member) > 0 && !is.null(shapes.for.sim) && length(shapes.for.sim) > 0) {
            # If sim points also used shapes, need new scale for data shapes
            if (!is.null(shapes.for.data) && length(shapes.for.data) > 0) rv <- rv + ggnewscale::new_scale("shape")
        }
        if (!is.null(color.data.shaded.colors) && length(color.data.shaded.colors) > 0) {
            rv <- rv + ggnewscale::new_scale_fill()
            rv <- rv + ggplot2::scale_fill_manual(name = "data color", values = color.data.shaded.colors, guide = ggplot2::guide_legend(override.aes = list(shape = 21)))
        }

        aes_map_point_data <- ggplot2::aes(x = year, y = value)
        hover_text_truth <- paste0(
            "Year: ", ifelse(is.numeric(df.truth$year) & !is.na(df.truth$year), ifelse(df.truth$year == floor(df.truth$year), sprintf("%d", df.truth$year), sprintf("%.1f", df.truth$year)), sprintf("%s", as.character(df.truth$year))),
            "\nValue: ", sprintf("%.2f", round(df.truth$value, 2)),
            ifelse("source" %in% names(df.truth) & !is.na(df.truth$source), sprintf("\nSource: %s", df.truth$source), ""),
            ifelse("data_url" %in% names(df.truth) & !is.na(df.truth$data_url), sprintf("\nURL: %s", df.truth$data_url), "")
        )
        aes_map_point_data$text <- hover_text_truth
        if ("color.and.shade.data.by" %in% names(df.truth)) aes_map_point_data$fill <- sym("color.and.shade.data.by")
        if ("shape.data.by" %in% names(df.truth)) aes_map_point_data$shape <- sym("shape.data.by")

        show_legend_data <- is.null(split.by) # Show legend for data points only if no split.by for sim
        rv <- rv + ggplot2::geom_point(data = df.truth, mapping = aes_map_point_data, size = 2, show.legend = show_legend_data)

        if (!is.null(all.shapes.for.scale) && length(all.shapes.for.scale) > 0) rv <- rv + ggplot2::scale_shape_manual(name = "data shape", values = all.shapes.for.scale)
    }

    if (style.manager$color.sim.by == "stratum" && is.null(split.by)) {
        # browser() # DEBUG: Before SIM ELEMENTS plotting # Removed this line
        rv <- rv + ggplot2::guides(color = "none") # Hide sim color legend if no actual split
    }

    #-- FACET --#
    facet_vars <- "outcome.display.name"
    if (!is.null(facet.by)) {
        valid_facet_cols <- paste0("facet.by", seq_along(facet.by))
        # Ensure these columns actually exist in one of the dataframes if they are to be used
        # This check is simplified; a more robust check would see if they exist in df.sim or df.truth if those are non-NULL
        # For now, assume they are created if facet.by is set.
        facet_vars <- c(facet_vars, valid_facet_cols)
    }

    # Check if data exists for faceting
    can_facet <- FALSE
    if (!is.null(df.sim) && nrow(df.sim) > 0 && all(facet_vars %in% names(df.sim))) can_facet <- TRUE
    if (!can_facet && !is.null(df.truth) && nrow(df.truth) > 0 && all(facet_vars %in% names(df.truth))) can_facet <- TRUE

    if (can_facet) {
        facet.formula <- as.formula(paste0("~", paste(facet_vars, collapse = " + ")))
        facet_args <- list(facet.formula, scales = "free_y")
        if (!is.null(n.facet.rows)) facet_args$nrow <- n.facet.rows
        if (!is.null(facet_labeller)) facet_args$labeller <- facet_labeller
        rv <- rv + do.call(ggplot2::facet_wrap, facet_args)
    }


    # --- START: Add ggplotly-compatible ribbons ---
    if (!is.null(df.sim.groupids.many.members) && nrow(df.sim.groupids.many.members) > 0 && summary.type != "individual.simulation" && all(c("value.lower", "value.upper") %in% names(df.sim.groupids.many.members))) {
        aes_map_ribbon <- ggplot2::aes(x = year, ymin = value.lower, ymax = value.upper, group = groupid)
        if ("color.sim.by" %in% names(df.sim.groupids.many.members)) aes_map_ribbon$fill <- sym("color.sim.by")

        rv <- rv + ggplot2::geom_ribbon(
            data = df.sim.groupids.many.members,
            mapping = aes_map_ribbon,
            alpha = style.manager$alpha.ribbon,
            inherit.aes = FALSE
        )
        # Add the fill scale specifically for the ribbon AFTER the geom_ribbon
        # Based on interactive testing, do NOT use ggnewscale here.
        if (!is.null(colors.for.sim) && length(colors.for.sim) > 0 && "color.sim.by" %in% names(df.sim.groupids.many.members)) {
            rv <- rv + ggplot2::scale_fill_manual(name = "sim fill", values = colors.for.sim, guide = "none")
        }
    }
    # --- END: Add ggplotly-compatible ribbons ---

    if (plot.year.lag.ratio) rv <- rv + ggplot2::xlab("latter year")

    rv
}

# plot.simulations_local is a wrapper around simplot_local for the plotly backend in plot_panel
# It's kept separate to mirror the structure of the original jheem package's plotting functions
plot.simulations_local <- function(...,
                                   outcomes = NULL,
                                   facet.by = NULL, # plot.simulations only has facet.by, not split.by
                                   dimension.values = list(),
                                   target.ontology = NULL,
                                   plot.which = c("sim.and.data", "sim.only")[1],
                                   summary.type = c("individual.simulation", "mean.and.interval", "median.and.interval")[1],
                                   title = "location",
                                   append.url = F, # Added to match simplot_local
                                   data.manager = get.default.data.manager(),
                                   style.manager = get.default.style.manager(),
                                   show.data.pull.error = F,
                                   debug = F) {
    # Call simplot_local, mapping arguments.
    # plot.simulations in the package does not have n.facet.rows or facet_labeller,
    # so those are not passed here. split.by is also not an arg for plot.simulations.
    simplot_local(...,
        outcomes = outcomes,
        corresponding.data.outcomes = NULL, # plot.simulations doesn't have this
        split.by = NULL, # plot.simulations does not split lines, only facets
        facet.by = facet.by,
        dimension.values = dimension.values,
        target.ontology = target.ontology,
        plot.which = plot.which,
        summary.type = summary.type,
        plot.year.lag.ratio = FALSE, # plot.simulations does not do year lag ratio
        title = title,
        append.url = append.url,
        data.manager = data.manager,
        style.manager = style.manager,
        show.data.pull.error = show.data.pull.error,
        debug = debug,
        facet_labeller = NULL # Not used by plot.simulations
    )
}
