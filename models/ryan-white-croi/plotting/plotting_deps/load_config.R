library(yaml)

# Environment for caching loaded configurations
.config_cache <- new.env(parent = emptyenv())

# CONTAINER MODIFICATION: Function to get config base path
get_config_base_path <- function() {
    # Check if we're in container environment
    if (file.exists("/app/plotting/config")) {
        return("/app/plotting/config")
    } else if (file.exists("plotting/config")) {
        return("plotting/config")
    } else if (file.exists("src/ui/config")) {
        # Fallback for interactive environment
        return("src/ui/config")
    } else {
        stop("Could not find config directory in any expected location")
    }
}

#' Load YAML configuration file
#' @param path Path to YAML file (relative to config base)
#' @return List containing configuration
load_yaml_file <- function(path) {
    # Build full path using config base
    config_base <- get_config_base_path()
    full_path <- file.path(config_base, path)
    
    # Debug print
    print(paste("Attempting to load:", full_path))

    # Check if file exists
    if (!isTRUE(file.exists(full_path))) {
        stop(sprintf("Configuration file not found: %s", full_path))
    }

    # Load and parse YAML
    tryCatch(
        {
            yaml::read_yaml(full_path)
        },
        error = function(e) {
            stop(sprintf("Error reading YAML file %s: %s", full_path, e$message))
        }
    )
}

#' Get base configuration (cached)
#' @return List containing base configuration
get_base_config <- function() {
    if (exists("base", envir = .config_cache)) {
        # print("Returning cached base config")
        return(.config_cache$base)
    } else {
        # print("Loading and caching base config")
        config <- load_yaml_file("base.yaml")  # Now relative to config base
        .config_cache$base <- config
        return(config)
    }
}

# Helper function to generate default display name by capitalizing words
.generate_default_display_name <- function(outcome_id) {
    words <- strsplit(outcome_id, "\\.")[[1]]
    capitalized_words <- sapply(words, function(word) {
        # Handle potential empty strings if there are multiple dots
        if (nchar(word) == 0) {
            return("")
        }
        paste0(toupper(substr(word, 1, 1)), substr(word, 2, nchar(word)))
    })
    # Filter out empty strings from multiple dots and join
    paste(capitalized_words[nchar(capitalized_words) > 0], collapse = " ")
}

#' Get dynamic outcomes from a simulation file
#' @param file_path Path to the simulation file
#' @param controls_config The loaded controls.yaml configuration (for display name mapping)
#' @return List of outcome configurations for YAML
get_dynamic_outcomes <- function(file_path, controls_config) {
    if (!file.exists(file_path)) {
        warning("Dynamic outcomes file does not exist: ", file_path)
        return(NULL)
    }

    # Load the RData file - should contain a simset object
    obj_name <- load(file_path)
    sim_data <- get(obj_name[1])

    # Check if it's a simset or contains a simset
    if (!is.null(sim_data$simset)) {
        sim_data <- sim_data$simset
    }

    # Get outcomes
    if (is.null(sim_data$outcomes)) {
        warning("No outcomes found in simset")
        return(NULL)
    }

    # Filter and format outcomes
    outcomes_to_show <- setdiff(sim_data$outcomes, c("infected", "uninfected"))
    outcomes_config <- list()

    # Get the display name map from the config, default to empty list if not present
    display_name_map <- controls_config$outcome_display_names %||% list()

    for (outcome in outcomes_to_show) {
        # Determine display name: Use map if available, otherwise generate default
        if (!is.null(display_name_map[[outcome]])) {
            display_name <- display_name_map[[outcome]]
        } else {
            # Fallback: Capitalize each word separated by '.'
            display_name <- .generate_default_display_name(outcome)
        }

        # Add to config structure
        outcome_entry <- list(
            id = outcome,
            label = display_name,
            description = paste("Outcome:", display_name)
        )

        # Add to options list with named entry
        option_name <- gsub("\\.", "_", outcome) # Create valid R name
        outcomes_config[[option_name]] <- outcome_entry
    }

    return(outcomes_config)
}

#' Get configuration for a specific component (controls & visualization components are cached)
#' @param component Name of the component
#' @return List containing component configuration
get_component_config <- function(component) {
    # Define components to cache
    cached_components <- c("controls", "visualization")
    cache_key <- component # Use component name as the cache key

    # Check cache if the component is designated for caching
    if (component %in% cached_components && exists(cache_key, envir = .config_cache)) {
        # print(paste("Returning cached config for component:", component))
        return(.config_cache[[cache_key]])
    }

    # Load from file if not designated for caching or not found in cache
    # print(paste("Loading config for component:", component))
    path <- file.path("components", paste0(component, ".yaml"))  # Now relative to config base
    config <- load_yaml_file(path)

    # Handle dynamic outcomes if this is the controls component
    if (component == "controls" && !is.null(config$dynamic_outcomes) && config$dynamic_outcomes) {
        # Get outcomes from file if specified
        if (!is.null(config$outcomes_file) && file.exists(config$outcomes_file)) {
            # Pass the loaded controls config (config) to the function
            dynamic_options <- get_dynamic_outcomes(config$outcomes_file, config)

            if (!is.null(dynamic_options) && length(dynamic_options) > 0) {
                # Replace the options section with dynamic outcomes
                config$plot_controls$outcomes$options <- dynamic_options
            }
        }
    }

    # Cache the component config if it's designated for caching
    if (component %in% cached_components) {
        # print(paste("Caching config for component:", component))
        .config_cache[[cache_key]] <- config
    }

    return(config)
}

#' Get default configuration (cached)
#' @return List containing default configuration
get_defaults_config <- function() {
    if (exists("defaults", envir = .config_cache)) {
        # print("Returning cached defaults config")
        return(.config_cache$defaults)
    } else {
        # print("Loading and caching defaults config")
        config <- load_yaml_file("defaults.yaml")  # Now relative to config base
        .config_cache$defaults <- config
        return(config)
    }
}

#' Get configuration for a specific page
#' @param page Name of the page
#' @return List containing page configuration
get_page_config <- function(page) {
    # Debug print
    print(paste("Loading config for page:", page))

    path <- file.path("pages", paste0(page, ".yaml"))  # Now relative to config base
    config <- load_yaml_file(path)
    return(config)
}

#' Get complete configuration for a page
#' @param page Name of the page
#' @return List containing complete configuration
get_page_complete_config <- function(page) {
    # Load all configurations
    base_config <- get_base_config()
    defaults_config <- get_defaults_config()
    page_config <- get_page_config(page)

    # Load component configs
    controls_config <- get_component_config("controls")

    # Merge configurations
    config <- merge_configs(base_config, defaults_config)
    config <- merge_configs(config, controls_config)
    config <- merge_configs(config, page_config)

    # Add page type
    config$page_type <- page

    # Validate the merged configuration
    validate_config(config)

    config
}

#' Merge configurations recursively
#' @param base Base configuration
#' @param override Configuration to merge on top
#' @return Merged configuration
merge_configs <- function(base, override) {
    if (is.null(override)) {
        return(base)
    }
    if (is.null(base)) {
        return(override)
    }

    if (!is.list(base) || !is.list(override)) {
        return(override)
    }

    merged <- base
    for (name in names(override)) {
        if (name %in% names(base) && is.list(base[[name]]) && is.list(override[[name]])) {
            merged[[name]] <- merge_configs(base[[name]], override[[name]])
        } else {
            merged[[name]] <- override[[name]]
        }
    }
    merged
}

#' Helper function to access nested configuration safely
#' @param config Configuration list
#' @param path Path to desired configuration (character vector)
#' @param default Default value if path not found
#' @return Configuration value or default
get_config_value <- function(config, path, default = NULL) {
    result <- config
    for (key in path) {
        if (!is.list(result) || is.null(result[[key]])) {
            return(default)
        }
        result <- result[[key]]
    }
    result
}

#' Format configuration value based on type
#' @param value Configuration value
#' @param type Expected type
#' @return Formatted value
format_config_value <- function(value, type) {
    switch(type,
        "numeric" = as.numeric(value),
        "logical" = as.logical(value),
        "character" = as.character(value),
        value
    )
}

#' Validate configuration structure
#' @param config Configuration to validate
#' @return TRUE if valid, throws error if invalid
validate_config <- function(config) {
    # Required sections for all configurations
    required <- c(
        "application",
        "theme",
        "defaults",
        "panels",
        "selectors"
    )

    # Check required sections
    missing <- setdiff(required, names(config))
    if (length(missing) > 0) {
        stop(sprintf(
            "Missing required configuration sections: %s",
            paste(missing, collapse = ", ")
        ))
    }

    # Page-specific validation based on page type
    if (!is.null(config$page_type)) {
        validate_page_config(config, config$page_type)
    }

    # Validate input types if present
    if (!is.null(config$input_types)) {
        for (type_name in names(config$input_types)) {
            type_config <- config$input_types[[type_name]]
            required_type_fields <- c("default_style", "multiple")
            missing <- setdiff(required_type_fields, names(type_config))
            if (length(missing) > 0) {
                stop(sprintf(
                    "Missing required fields for input type %s: %s",
                    type_name,
                    paste(missing, collapse = ", ")
                ))
            }
        }
    }

    TRUE
}

#' Validate page-specific configuration
#' @param config Configuration to validate
#' @param page Page type
#' @return TRUE if valid, throws error if invalid
validate_page_config <- function(config, page) {
    # Basic validation of config structure
    if (!is.list(config)) {
        stop("Configuration must be a list")
    }
    TRUE
}

#' Get configuration for a specific selector
#' @param selector_id Selector identifier
#' @param page_type Page type ("prerun" or "custom")
#' @param config Pre-loaded complete page configuration object
#' @param group_num Optional group number for custom page
#' @return Selector configuration
get_selector_config <- function(selector_id, page_type, config, group_num = NULL) {
    # Debug print
    print(paste("Getting config for selector:", selector_id))
    print(paste("Page type:", page_type))
    print(paste("Group num:", group_num))

    # Validate inputs
    if (!is.character(page_type) || length(page_type) != 1) {
        stop("page_type must be a single character string")
    }
    if (!is.character(selector_id) || length(selector_id) != 1) {
        stop("selector_id must be a single character string")
    }
    if (!is.null(group_num) && (!is.numeric(group_num) || length(group_num) != 1)) {
        stop("group_num must be NULL or a single number")
    }
    if (missing(config) || !is.list(config)) {
        stop("get_selector_config requires a valid 'config' object.")
    }

    # Use the provided config object directly
    # config <- get_page_complete_config(page_type) # REMOVED

    # Get input type defaults
    input_types <- config$input_types %||% list()

    # Get base selector configuration based on context
    selector_config <- if (page_type == "custom" && !is.null(group_num)) {
        if (selector_id %in% c("age_groups", "race_ethnicity", "biological_sex", "risk_factor")) {
            # Demographics selectors
            config$demographics[[selector_id]]
        } else if (selector_id == "intervention_dates") {
            # Date selector
            config$interventions$dates
        } else if (selector_id %in% names(config$interventions$components)) {
            # Any intervention component from the config
            config$interventions$components[[selector_id]]
        } else {
            # Standard selectors
            config$selectors[[selector_id]]
        }
    } else {
        config$selectors[[selector_id]]
    }

    if (is.null(selector_config)) {
        # Debug print of available configurations
        print("Available configurations:")
        print("Demographics:")
        print(names(config$demographics))
        print("Intervention components:")
        print(names(config$interventions$components))
        print("Selectors:")
        print(names(config$selectors))
        stop(sprintf("No configuration found for selector: %s", selector_id))
    }

    # Merge with input type defaults if applicable
    if (!is.null(selector_config$type) && !is.null(input_types[[selector_config$type]])) {
        type_defaults <- input_types[[selector_config$type]]
        selector_config$input_style <- selector_config$input_style %||% type_defaults$default_style
        selector_config$multiple <- selector_config$multiple %||% type_defaults$multiple
    }

    # Generate ID with group number if provided
    id <- if (!is.null(group_num)) {
        paste("int", selector_id, group_num, page_type, sep = "_")
    } else {
        paste("int", selector_id, page_type, sep = "_")
    }

    # Add generated ID to config
    selector_config$id <- id

    selector_config
}

#' Get model dimension mapping
#' @param dimension Dimension name (age, sex, risk, race)
#' @param ui_value UI value to map
#' @return Model value
get_model_dimension_value <- function(dimension, ui_value) {
    config <- get_defaults_config()
    mappings <- config$model_dimensions[[dimension]]$mappings

    if (is.null(mappings[[ui_value]])) {
        stop(sprintf("No mapping found for %s value: %s", dimension, ui_value))
    }

    mappings[[ui_value]]
}

#' Source the model specification file from appropriate location
#' @return NULL invisibly
source_model_specification <- function() {
    # Get model specification config from base config
    base_config <- get_base_config()
    model_config <- base_config$model_specification

    if (is.null(model_config)) {
        stop("Model specification configuration not found in base.yaml")
    }

    # Get file paths from config
    main_file <- model_config$main_file
    dev_path <- model_config$development_path
    deploy_path <- model_config$deployment_path
    model_name <- model_config$name

    # Construct full paths
    external_path <- file.path(dev_path, main_file)
    internal_path <- file.path(deploy_path, main_file)

    # Try to source the file
    if (file.exists(external_path)) {
        message(paste0("Sourcing ", model_name, " specification from development path"))
        source(external_path)
    } else if (file.exists(internal_path)) {
        message(paste0("Sourcing ", model_name, " specification from deployment path"))
        source(internal_path)
    } else {
        stop(paste0(
            model_name, " specification file not found in either location: ",
            external_path, " or ", internal_path
        ))
    }

    invisible(NULL)
}
