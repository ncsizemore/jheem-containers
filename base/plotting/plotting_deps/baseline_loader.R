# src/data/loaders/baseline_loader.R

#' Load baseline simulation using appropriate provider
#' @param page_id Page identifier ("prerun" or "custom")
#' @param settings Settings to determine appropriate baseline (needs location)
#' @return Baseline simulation set or NULL if not available/enabled
load_baseline_simulation <- function(page_id, settings) {
  # Check if we have a cached version already
  # Use a simple global variable to track loaded baselines by location
  if (!exists(".BASELINE_CACHE", envir = .GlobalEnv)) {
    assign(".BASELINE_CACHE", list(), envir = .GlobalEnv) 
  }
  
  # Try to get from cache first
  cache_key <- paste0(page_id, "_", settings$location, "_base")
  print(sprintf("[BASELINE] Checking for cached baseline with key: %s", cache_key))
  
  if (cache_key %in% names(get(".BASELINE_CACHE", envir = .GlobalEnv))) {
    print(sprintf("[BASELINE] Found cached baseline for %s, returning without reloading", cache_key))
    return(get(".BASELINE_CACHE", envir = .GlobalEnv)[[cache_key]])
  }
  
  print(sprintf("[BASELINE] No cached baseline found for %s, loading from provider", cache_key))
  # Early return if settings missing location
  if (is.null(settings) || is.null(settings$location)) {
    warning("Cannot load baseline: settings missing location")
    return(NULL)
  }

  # Get visualization config for baseline
  vis_config <- tryCatch(
    {
      get_component_config("visualization")
    },
    error = function(e) {
      warning(paste("Error loading visualization config:", e$message))
      return(NULL)
    }
  )

  # Check if baseline is enabled
  if (is.null(vis_config) ||
    is.null(vis_config$baseline_simulations) ||
    !vis_config$baseline_simulations$enabled ||
    is.null(vis_config$baseline_simulations[[page_id]]) ||
    !vis_config$baseline_simulations[[page_id]]$enabled) {
    print("[BASELINE] Baseline simulations not enabled in config")
    return(NULL)
  }
  
  # Check if we should reuse the base simulation for custom interventions
  if (page_id == "custom" && 
      !is.null(vis_config$baseline_simulations$custom$reuse_base_simset) && 
      vis_config$baseline_simulations$custom$reuse_base_simset) {
    print("[BASELINE] Custom intervention is configured to reuse base simulation")
    # Return NULL here - will handle at higher level
    return(NULL)
  }

  # Get baseline config for this page
  baseline_config <- vis_config$baseline_simulations[[page_id]]

  # Get page-specific config
  page_config <- tryCatch(
    {
      get_page_complete_config(page_id)
    },
    error = function(e) {
      warning(paste("Error loading page config:", e$message))
      return(NULL)
    }
  )

  # Create appropriate settings for baseline - only use location
  baseline_settings <- list(
    location = settings$location
  )

  # Create provider of appropriate type
  provider_type <- if (baseline_config$use_provider) {
    # Use same provider as page
    if (page_id == "prerun") {
      page_config$prerun_simulations$provider
    } else {
      page_config$custom_simulations$provider
    }
  } else {
    # Use specified provider
    baseline_config$provider %||% "local"
  }

  # Get file pattern from config, with fallbacks
  file_pattern <- baseline_config$file_pattern
  if (is.null(file_pattern)) {
    file_pattern <- vis_config$baseline_simulations$default_file_pattern
  }
  if (is.null(file_pattern)) {
    file_pattern <- "base/{location}_base.Rdata"
  }

  # Create provider config
  provider_config <- list(
    file_pattern = file_pattern
  )

  # If provider uses config file, include it
  if (page_id == "prerun") {
    provider_config$config_file <- page_config$prerun_simulations$config_file
  } else {
    provider_config$config_file <- page_config$custom_simulations$config_file
  }

  print(sprintf(
    "[BASELINE] Using provider: %s with file pattern: %s",
    provider_type, file_pattern
  ))

  # Create provider
  provider <- NULL
  if (provider_type == "local") {
    provider <- LocalProvider$new(config = provider_config, mode = page_id)
  } else if (provider_type == "onedrive") {
    provider <- OneDriveProvider$new(config = provider_config, mode = page_id)
  } else {
    warning(paste("Unknown provider type:", provider_type))
    return(NULL)
  }

  # Get label from config, with fallbacks
  label <- baseline_config$label
  if (is.null(label)) {
    label <- vis_config$baseline_simulations$default_label
  }
  if (is.null(label)) {
    label <- "Baseline (No Intervention)"
  }

  # Try to load the baseline simulation
  tryCatch(
  {
  print(sprintf(
  "[BASELINE] Loading baseline simulation for location: %s",
  settings$location
  ))

  baseline_simset <- provider$load_simset(baseline_settings)

  # Just log success instead of trying to set names
  if (!is.null(baseline_simset)) {
  print("[BASELINE] Successfully loaded baseline simulation")
    
            # Cache the result for future use
    cache <- get(".BASELINE_CACHE", envir = .GlobalEnv)
      cache[[cache_key]] <- baseline_simset
      assign(".BASELINE_CACHE", cache, envir = .GlobalEnv)
    print(sprintf("[BASELINE] Cached baseline simulation with key: %s", cache_key))
  }

      baseline_simset
        },
        error = function(e) {
          warning(paste("Failed to load baseline simulation:", e$message))
          NULL
        }
      )
}