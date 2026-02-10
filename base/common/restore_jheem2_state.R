# restore_jheem2_state.R - Restore jheem2 internal state from workspace
# This should be called after loading the workspace in the container

restore_jheem2_state <- function() {
  cat("🔄 Restoring jheem2 internal state...\n")
  
  if (!exists(".jheem2_state", envir = .GlobalEnv)) {
    cat("⚠️  No .jheem2_state found in workspace\n")
    return(FALSE)
  }
  
  state <- get(".jheem2_state", envir = .GlobalEnv)
  
  # Restore VERSION.MANAGER
  if (!is.null(state$version_manager)) {
    vm <- asNamespace("jheem2")$VERSION.MANAGER
    for (name in names(state$version_manager)) {
      assign(name, state$version_manager[[name]], envir = vm)
    }
    cat("  ✅ VERSION.MANAGER restored\n")
  }
  
  # Restore ONTOLOGY.MAPPING.MANAGER
  if (!is.null(state$ontology_mapping_manager)) {
    ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
    
    # Restore mappings
    if (!is.null(state$ontology_mapping_manager$mappings)) {
      ont_mgr$mappings <- state$ontology_mapping_manager$mappings
      cat("  ✅ Restored", length(ont_mgr$mappings), "ontology mappings\n")
      if (length(ont_mgr$mappings) > 0) {
        cat("    🔍 Mapping names:", paste(names(ont_mgr$mappings), collapse = ", "), "\n")
      }
    }
    
    # Restore caches
    if (!is.null(state$ontology_mapping_manager$cached.one.way.mappings)) {
      ont_mgr$cached.one.way.mappings <- state$ontology_mapping_manager$cached.one.way.mappings
    }
    if (!is.null(state$ontology_mapping_manager$cached.two.way.mappings)) {
      ont_mgr$cached.two.way.mappings <- state$ontology_mapping_manager$cached.two.way.mappings
    }
    
    cat("  ✅ ONTOLOGY.MAPPING.MANAGER restored\n")
  }
  
  cat("🎯 jheem2 state restoration complete!\n")
  return(TRUE)
}

# Make the function available globally
assign("restore_jheem2_state", restore_jheem2_state, envir = .GlobalEnv)
