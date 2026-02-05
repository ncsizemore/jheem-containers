# tests/test_simulation.R
# Test file for simulation pipeline components

#' Test the complete simulation pipeline
#' @param base_simulation_path Path to base simulation file
test_simulation_pipeline <- function(base_simulation_path = "/app/test_base_sim.rdata") {
  
  cat("🧪 Testing complete simulation pipeline...\n")
  
  # Test parameters
  test_parameters <- list(
    adap_suppression_loss = 50,
    oahs_suppression_loss = 30, 
    other_suppression_loss = 40
  )
  
  test_city <- "C.12580"
  
  tryCatch({
    # Step 1: Test base simulation loading
    cat("  📦 Testing base simulation loading...\n")
    if (!file.exists(base_simulation_path)) {
      stop("Test base simulation file not found: ", base_simulation_path)
    }
    
    # Load the .rdata file and get the simulation object
    loaded_objects <- load(base_simulation_path)
    cat("    Loaded objects:", paste(loaded_objects, collapse = ", "), "\n")
    
    # Get the first loaded object (should be the simulation set)
    base_simset <- get(loaded_objects[1])
    cat("✅ Base simulation loaded with class:", class(base_simset), "\n")
    
    # Step 2: Test intervention creation
    cat("  🔧 Testing intervention creation...\n")
    intervention <- create_ryan_white_intervention(test_parameters)
    cat("    ✅ Intervention created\n")
    
    # Step 3: Test simulation execution
    cat("  🚀 Testing simulation execution...\n")
    results <- run_custom_simulation(base_simset, intervention)
    cat("    ✅ Simulation completed\n")
    
    # Step 4: Test plot generation
    cat("  📊 Testing plot generation...\n")
    plots <- generate_simulation_plots(results, test_city, test_parameters, base_simset)
    cat("    ✅ Plots generated\n")
    
    # Return test results
    test_results <- list(
      success = TRUE,
      city = test_city,
      parameters = test_parameters,
      num_plots = length(plots),
      plots = names(plots)
    )
    
    cat("🎉 Pipeline test completed successfully!\n")
    return(test_results)
    
  }, error = function(e) {
    cat("❌ Pipeline test failed:", e$message, "\n")
    return(list(
      success = FALSE,
      error = e$message
    ))
  })
}

cat("📦 Test module loaded\n")
