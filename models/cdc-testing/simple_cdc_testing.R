# simulation/simple_cdc_testing.R
# CDC Testing intervention creation using direct jheem2 calls.
# Implements the model-agnostic contract expected by custom_simulation.R:
#   create_model_intervention() - reads env vars, returns intervention
#   run_custom_simulation(base_simset, intervention) - returns results simset
#
# Based on Shiny app's model_effects.R (lines 155-230) and research script
# patterns from cdc_testing_interventions.R

# ============================================================================
# WORKAROUND FOR JHEEM2 TYPO
# ============================================================================

get.intervention.from.code.from.code <- function(...) {
  get.intervention.from.code(...)
}

# ============================================================================
# CDC TESTING INTERVENTION PARAMETERS
# ============================================================================

# Constants (CDC.TESTING.ANCHOR.YEAR = 2025, start = anchor + 0.75)
CDC.TESTING.START.YEAR <- 2025.75
CDC.TESTING.LOSS.LAG <- 0.25

# ============================================================================
# CONTRACT: create_model_intervention / run_custom_simulation
# ============================================================================

#' Create CDC Testing intervention.
#' Reads TESTING_REDUCTION and PROPORTION_TESTED from environment variables.
#' @return jheem2 intervention object
create_model_intervention <- function() {
  testing_reduction <- as.numeric(Sys.getenv("TESTING_REDUCTION", "100"))
  proportion_tested <- as.numeric(Sys.getenv("PROPORTION_TESTED", "50"))

  cat(sprintf("  Creating CDC Testing intervention: reduction=%g%%, proportion_tested=%g%%\n",
              testing_reduction, proportion_tested))

  # Effect 1: CDC testing reduction
  # 100% reduction -> cdc.effect = 0 (no CDC testing)
  # 50% reduction -> cdc.effect = 0.5 (half CDC testing)
  # 0% reduction -> cdc.effect = 1 (full CDC testing)
  cdc_effect <- create.intervention.effect(
    quantity.name = "cdc.effect",
    start.time = CDC.TESTING.START.YEAR,
    effect.values = 1 - (testing_reduction / 100),
    times = CDC.TESTING.START.YEAR + CDC.TESTING.LOSS.LAG,
    scale = "proportion",
    apply.effects.as = "value",
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = FALSE
  )

  # Effect 2: Proportion tested regardless of CDC funding
  # Baseline parameter — active from simulation start
  proportion_effect <- create.intervention.effect(
    quantity.name = "proportion.tested.regardless",
    start.time = 2015,
    effect.values = proportion_tested / 100,
    times = 2015.25,
    scale = "proportion",
    apply.effects.as = "value",
    allow.values.less.than.otherwise = TRUE,
    allow.values.greater.than.otherwise = TRUE
  )

  intervention <- create.intervention(
    cdc_effect,
    proportion_effect,
    WHOLE.POPULATION,
    code = "cdct-custom"
  )

  cat("  CDC Testing intervention created (code: cdct-custom)\n")
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
