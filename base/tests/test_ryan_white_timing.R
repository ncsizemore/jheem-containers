#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) == 1) {
  test_file <- normalizePath(sub("^--file=", "", script_arg))
  repository_root <- dirname(dirname(test_file))
} else {
  repository_root <- normalizePath(".")
}
script_path <- file.path(repository_root, "simulation", "simple_ryan_white.R")

set_timing_env <- function(start_time, lag, simulation_start, simulation_end,
                           reporting_start, reporting_end) {
  Sys.setenv(
    INTERVENTION_TYPE = "permanent_cessation",
    INTERVENTION_START_TIME = as.character(start_time),
    LOSS_LAG_YEARS = as.character(lag),
    SIMULATION_START_YEAR = as.character(simulation_start),
    SIMULATION_END_YEAR = as.character(simulation_end),
    REPORTING_START_YEAR = as.character(reporting_start),
    REPORTING_END_YEAR = as.character(reporting_end)
  )
}

set_timing_env(2026.5, 0.25, 2026, 2036, 2026, 2031)
source(script_path, local = environment())

stopifnot(
  identical(START.YEAR, 2026.5),
  identical(LOSS.LAG, 0.25),
  identical(SIMULATION.START.YEAR, 2026),
  identical(SIMULATION.END.YEAR, 2036),
  identical(REPORTING.START.YEAR, 2026),
  identical(REPORTING.END.YEAR, 2031)
)

set_timing_env(2026.5, 0.25, 2026, 2036, 2026, 2037)
invalid_reporting_error <- tryCatch(
  {
    source(script_path, local = new.env(parent = globalenv()))
    NULL
  },
  error = function(error) error
)
stopifnot(
  inherits(invalid_reporting_error, "error"),
  grepl("reporting period", invalid_reporting_error$message, fixed = TRUE)
)

Sys.unsetenv("INTERVENTION_START_TIME")
missing_timing_error <- tryCatch(
  {
    source(script_path, local = new.env(parent = globalenv()))
    NULL
  },
  error = function(error) error
)
stopifnot(
  inherits(missing_timing_error, "error"),
  grepl("INTERVENTION_START_TIME", missing_timing_error$message, fixed = TRUE)
)

cat("Ryan White custom-simulation timing contract passed\n")
