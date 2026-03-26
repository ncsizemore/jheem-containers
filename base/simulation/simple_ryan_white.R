# simulation/simple_ryan_white.R
# Ryan White intervention creation using direct jheem2 calls.
# Implements the model-agnostic contract expected by custom_simulation.R:
#   create_model_intervention() - reads env vars, returns intervention
#   run_custom_simulation(base_simset, intervention) - returns results simset
#
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
# CONTRACT: create_model_intervention / run_custom_simulation
# ============================================================================

#' Create Ryan White intervention using direct jheem2 calls.
#' Reads ADAP_LOSS, OAHS_LOSS, OTHER_LOSS from environment variables.
#' @return jheem2 intervention object
create_model_intervention <- function() {
  adap_loss <- as.numeric(Sys.getenv("ADAP_LOSS", "50"))
  oahs_loss <- as.numeric(Sys.getenv("OAHS_LOSS", "30"))
  other_loss <- as.numeric(Sys.getenv("OTHER_LOSS", "40"))

  cat(sprintf("  Creating Ryan White intervention: ADAP=%g%%, OAHS=%g%%, Other=%g%%\n",
              adap_loss, oahs_loss, other_loss))
  
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
  
  intervention <- create.intervention(
    adap.expansion.effect,
    adap.nonexpansion.effect,
    oahs.expansion.effect,
    oahs.nonexpansion.effect,
    rw.support.expansion.effect,
    rw.support.nonexpansion.effect,
    WHOLE.POPULATION,
    code = "rw-custom"
  )

  cat("  Ryan White intervention created (code: rw-custom)\n")
  return(intervention)
}

#' Run custom simulation
#' @param base_simset jheem2 simulation set
#' @param intervention jheem2 intervention object
#' @return jheem2 simulation results
run_custom_simulation <- function(base_simset, intervention) {
  cat(sprintf("  Running simulation (simset class: %s, intervention: %s)\n",
              class(base_simset), intervention$code))

  base_simset <- copy.simulation.set(base_simset)

  # jheem2 sometimes reports inconsistent totals, so track the max seen
  progress_state <- list(max_total = 0, last_index = -1)
  progress_callback <- function(index, total, done) {
    if (total > progress_state$max_total)
      progress_state$max_total <<- total
    if (index > progress_state$last_index && index <= progress_state$max_total) {
      percentage <- round((index / progress_state$max_total) * 100)
      cat(sprintf("  Progress: %d of %d (%d%%)\n", index, progress_state$max_total, percentage))
      progress_state$last_index <<- index
    }
    if (done) cat("  Simulation batch completed\n")
  }

  results <- intervention$run(base_simset,
                              start.year = 2025,
                              end.year = 2035,
                              verbose = TRUE,
                              listener = progress_callback)

  cat("  Simulation completed\n")
  return(results)
}