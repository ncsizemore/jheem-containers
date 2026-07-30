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

# Timing is model-specific. It must be supplied by the model image/backend
# contract; silently inheriting the MSA/AJPH timeline caused CROI custom
# simulations to begin a year early.
read_required_numeric_env <- function(name) {
  raw_value <- Sys.getenv(name, "")
  if (raw_value == "") {
    stop(sprintf("Required environment variable not set: %s", name))
  }

  value <- suppressWarnings(as.numeric(raw_value))
  if (length(value) != 1 || !is.finite(value)) {
    stop(sprintf("Environment variable %s must be a finite number (received '%s')",
                 name, raw_value))
  }

  value
}

read_required_integer_year <- function(name) {
  value <- read_required_numeric_env(name)
  if (value != floor(value)) {
    stop(sprintf("Environment variable %s must be a whole-number year", name))
  }
  value
}

INTERVENTION.TYPE <- Sys.getenv("INTERVENTION_TYPE", "")
if (INTERVENTION.TYPE != "permanent_cessation") {
  stop("Ryan White custom simulations require INTERVENTION_TYPE=permanent_cessation")
}

START.YEAR <- read_required_numeric_env("INTERVENTION_START_TIME")
LOSS.LAG <- read_required_numeric_env("LOSS_LAG_YEARS")
SIMULATION.START.YEAR <- read_required_integer_year("SIMULATION_START_YEAR")
SIMULATION.END.YEAR <- read_required_integer_year("SIMULATION_END_YEAR")
REPORTING.START.YEAR <- read_required_integer_year("REPORTING_START_YEAR")
REPORTING.END.YEAR <- read_required_integer_year("REPORTING_END_YEAR")

if (LOSS.LAG < 0) stop("LOSS_LAG_YEARS cannot be negative")
if (SIMULATION.START.YEAR >= SIMULATION.END.YEAR) {
  stop("SIMULATION_START_YEAR must be earlier than SIMULATION_END_YEAR")
}
if (START.YEAR < SIMULATION.START.YEAR || START.YEAR > SIMULATION.END.YEAR) {
  stop("INTERVENTION_START_TIME must fall within the simulation period")
}
if (REPORTING.START.YEAR < SIMULATION.START.YEAR ||
    REPORTING.END.YEAR > SIMULATION.END.YEAR ||
    REPORTING.START.YEAR > REPORTING.END.YEAR) {
  stop("The reporting period must be ordered and contained within the simulation period")
}

cat(sprintf(
  "  Ryan White timing: intervention=%g, loss lag=%g years, simulation=%d-%d, reporting=%d-%d\n",
  START.YEAR, LOSS.LAG, SIMULATION.START.YEAR, SIMULATION.END.YEAR,
  REPORTING.START.YEAR, REPORTING.END.YEAR
))

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
                              start.year = SIMULATION.START.YEAR,
                              end.year = SIMULATION.END.YEAR,
                              verbose = TRUE,
                              listener = progress_callback)

  cat("  Simulation completed\n")
  return(results)
}
