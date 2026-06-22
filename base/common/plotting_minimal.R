# Minimal plotting utilities for JHEEM container
# Simplified version of plotting_local.R for container testing

library(plotly)
library(jsonlite)

# Simple wrapper function for basic plot testing
create_test_plot <- function(data, title = "Test Plot") {
  tryCatch({
    p <- plot_ly(data, x = ~x, y = ~y, type = 'scatter', mode = 'lines+markers') %>%
      layout(title = title, xaxis = list(title = "X"), yaxis = list(title = "Y"))
    
    # Convert to JSON format expected by frontend
    plot_json <- list(
      data = p$x$data,
      layout = p$x$layout
    )
    
    return(list(
      success = TRUE,
      plot = p,
      json = toJSON(plot_json, auto_unbox = TRUE, pretty = TRUE)
    ))
  }, error = function(e) {
    return(list(
      success = FALSE,
      error = e$message
    ))
  })
}

# Test function to validate plotting works
test_plotting_functionality <- function() {
  cat("🧪 Testing basic plotting functionality...\n")
  
  # Create test data
  test_data <- data.frame(
    x = 1:10,
    y = sin(1:10) + rnorm(10, 0, 0.1)
  )
  
  # Test plot creation
  result <- create_test_plot(test_data, "Sine Wave Test")
  
  if (result$success) {
    cat("✅ Plot creation successful\n")
    cat("📊 JSON length:", nchar(result$json), "characters\n")
    return(TRUE)
  } else {
    cat("❌ Plot creation failed:", result$error, "\n")
    return(FALSE)
  }
}

cat("📦 Minimal plotting utilities loaded\n")
