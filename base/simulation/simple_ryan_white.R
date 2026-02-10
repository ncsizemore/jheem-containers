# simulation/simple_ryan_white.R
# Simplified Ryan White intervention creation using direct jheem2 calls
# Based on research script patterns from ryan_white_interventions.R lines 250-327

# ============================================================================
# WORKAROUND FOR JHEEM2 TYPO
# ============================================================================

# Fix for jheem2 package typo where it looks for "get.intervention.from.code.from.code"
# instead of the correct "get.intervention.from.code"
get.intervention.from.code.from.code <- function(...) {
  get.intervention.from.code(...)
}

# ============================================================================
# RYAN WHITE INTERVENTION PARAMETERS
# ============================================================================

# Constants matching research script
START.YEAR <- 2025.5
LOSS.LAG <- 0.25

# ============================================================================
# SIMPLIFIED INTERVENTION CREATION
# ============================================================================

#' Create Ryan White intervention using direct jheem2 calls
#' @param parameters List with adap_suppression_loss, oahs_suppression_loss, other_suppression_loss
#' @return jheem2 intervention object
create_ryan_white_intervention <- function(parameters) {
  cat("🔧 Creating Ryan White intervention with direct jheem2 calls...\n")
  
  # Extract parameters with defaults
  adap_loss <- parameters$adap_suppression_loss %||% 30
  oahs_loss <- parameters$oahs_suppression_loss %||% 25
  other_loss <- parameters$other_suppression_loss %||% 40
  
  cat("  📊 Parameters: ADAP=", adap_loss, "%, OAHS=", oahs_loss, "%, Other=", other_loss, "%\n")
  
  cat("  🔍 Determining number of simulations needed for parameter matrix...\n")
  # We need to create parameters that will match the base simulation set
  # For now, we'll use NULL parameters (simplest approach matching our direct numeric values)
  rw_params <- NULL
  
  cat("  📊 Using direct numeric values instead of parameter matrix\n")
  
  cat("  🎯 Creating 6 intervention effects (expansion/nonexpansion × adap/oahs/other)...\n")
  
  # Create ADAP effects (direct jheem2 calls matching research script)
  adap.expansion.effect <- create.intervention.effect(
    quantity.name = 'adap.suppression.expansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (adap_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion', 
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  adap.nonexpansion.effect <- create.intervention.effect(
    quantity.name = 'adap.suppression.nonexpansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (adap_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion',
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  # Create OAHS effects
  oahs.expansion.effect <- create.intervention.effect(
    quantity.name = 'oahs.suppression.expansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (oahs_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion',
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  oahs.nonexpansion.effect <- create.intervention.effect(
    quantity.name = 'oahs.suppression.nonexpansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (oahs_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion',
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  # Create RW Support (Other) effects
  rw.support.expansion.effect <- create.intervention.effect(
    quantity.name = 'rw.support.suppression.expansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (other_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion',
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  rw.support.nonexpansion.effect <- create.intervention.effect(
    quantity.name = 'rw.support.suppression.nonexpansion.effect',
    start.time = START.YEAR,
    effect.values = 1 - (other_loss / 100),
    apply.effects.as = 'value',
    scale = 'proportion',
    times = START.YEAR + LOSS.LAG,
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )
  
  cat("  ✅ All 6 intervention effects created\n")
  
  # Create complete intervention (matching research script pattern)
  cat("  🎯 Creating complete intervention with WHOLE.POPULATION...\n")
  intervention <- create.intervention(
    adap.expansion.effect,
    adap.nonexpansion.effect,
    oahs.expansion.effect,
    oahs.nonexpansion.effect,
    rw.support.expansion.effect,
    rw.support.nonexpansion.effect,
    parameters = rw_params,
    WHOLE.POPULATION,
    code = "rw-custom"
  )
  
  cat("✅ Ryan White intervention created successfully with code 'rw-custom'\n")
  return(intervention)
}

#' Run custom simulation using direct jheem2 calls
#' @param base_simset jheem2 simulation set
#' @param intervention jheem2 intervention object
#' @return jheem2 simulation results
run_custom_simulation <- function(base_simset, intervention) {
  cat("🚀 Running custom simulation with direct run.intervention() call...\n")
  
  # Validate inputs
  if (is.null(base_simset)) {
    stop("Base simulation set cannot be null")
  }
  if (is.null(intervention)) {
    stop("Intervention cannot be null")
  }
  
  cat("  📦 Base simset class:", class(base_simset), "\n")
  cat("  🔧 Intervention code:", intervention$code, "\n")
  
  # Copy simset to avoid modifying original (like the old complex approach)
  cat("  🔧 Copying simulation set to avoid modifying original...\n")
  base_simset <- copy.simulation.set(base_simset)
  
  # Create progress callback for monitoring (like the complex approach)
  # Note: jheem2 sometimes reports inconsistent totals, so we track the max total seen
  progress_state <- list(max_total = 0, last_index = -1)
  
  progress_callback <- function(index, total, done) {
    # Update max total if we see a larger one
    if (total > progress_state$max_total) {
      progress_state$max_total <<- total
    }
    
    # Only report progress if index has actually increased and is reasonable
    if (index > progress_state$last_index && index <= progress_state$max_total) {
      percentage <- round((index / progress_state$max_total) * 100)
      cat("  🔄 Simulation progress:", index, "of", progress_state$max_total, paste0("(", percentage, "%)"), "\n")
      progress_state$last_index <<- index
    }
    
    if (done) {
      cat("  ✅ Simulation batch completed!\n")
    }
  }
  
  # Direct jheem2 call using intervention's run method (matching research script)
  cat("  🎯 Calling intervention$run() with progress tracking...\n")
  results <- intervention$run(base_simset, 
                             start.year = 2025, 
                             end.year = 2035, 
                             verbose = TRUE,
                             listener = progress_callback)
  
  cat("✅ Custom simulation completed successfully\n")
  cat("  📊 Results class:", class(results), "\n")
  
  return(results)
}

#' Validate intervention parameters
#' @param parameters List of parameters to validate
validate_intervention_parameters <- function(parameters) {
  cat("🔍 Validating intervention parameters...\n")
  
  # Check required parameters
  required_params <- c("adap_suppression_loss", "oahs_suppression_loss", "other_suppression_loss")
  missing_params <- required_params[!required_params %in% names(parameters)]
  
  if (length(missing_params) > 0) {
    stop("Missing required parameters: ", paste(missing_params, collapse = ", "))
  }
  
  # Validate parameter ranges (0-100%)
  for (param in required_params) {
    value <- parameters[[param]]
    if (!is.numeric(value) || value < 0 || value > 100) {
      stop("Parameter ", param, " must be between 0 and 100, got: ", value)
    }
  }
  
  cat("✅ All parameters validated successfully\n")
}