# baseline_loading.R
# Direct baseline loading bypassing provider system

load_baseline_direct <- function(city, page_id = "prerun") {
  # Check cache first
  if (!exists(".BASELINE_CACHE", envir = .GlobalEnv)) {
    assign(".BASELINE_CACHE", list(), envir = .GlobalEnv) 
  }
  
  cache_key <- paste0(page_id, "_", city, "_base")
  print(sprintf("[BASELINE] Checking for cached baseline with key: %s", cache_key))
  
  if (cache_key %in% names(get(".BASELINE_CACHE", envir = .GlobalEnv))) {
    print(sprintf("[BASELINE] Found cached baseline for %s, returning without reloading", cache_key))
    return(get(".BASELINE_CACHE", envir = .GlobalEnv)[[cache_key]])
  }
  
  print(sprintf("[BASELINE] No cached baseline found for %s, loading directly from file", cache_key))
  
  # Construct direct file path
  baseline_file <- file.path("simulations/ryan-white/base", paste0(city, "_base.Rdata"))
  
  if (!file.exists(baseline_file)) {
    warning(sprintf("Baseline file not found: %s", baseline_file))
    return(NULL)
  }
  
  print(sprintf("[BASELINE] Loading baseline simulation from: %s", baseline_file))
  
  # Load baseline simulation directly
  baseline_simset <- tryCatch({
    loaded_data <- load(baseline_file)
    loaded_obj <- get(loaded_data[1])
    
    if (is.null(loaded_obj)) {
      warning("Loaded baseline object is NULL")
      return(NULL)
    }
    
    print("[BASELINE] Successfully loaded baseline simulation")
    
    # Cache the result for future use
    cache <- get(".BASELINE_CACHE", envir = .GlobalEnv)
    cache[[cache_key]] <- loaded_obj
    assign(".BASELINE_CACHE", cache, envir = .GlobalEnv)
    print(sprintf("[BASELINE] Cached baseline simulation with key: %s", cache_key))
    
    loaded_obj
  }, error = function(e) {
    warning(sprintf("Failed to load baseline simulation from %s: %s", baseline_file, e$message))
    NULL
  })
  
  return(baseline_simset)
}
