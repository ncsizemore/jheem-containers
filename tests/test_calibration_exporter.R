source("calibration/ryan-white/export_calibration.R")

posterior <- array(
  c(1, 3, 5, 7, 9, 2, 4, 6, 8, 10),
  dim = c(year = 2, sim = 5),
  dimnames = list(year = c("2020", "2021"), sim = as.character(1:5))
)
records <- posterior_records(posterior)
stopifnot(length(records) == 2L)
stopifnot(is.null(names(records)))
stopifnot(identical(records[[1]]$year, 2020L))
stopifnot(is.list(records[[1]]$stratum), !is.null(names(records[[1]]$stratum)))
stopifnot(records[[1]]$q025 <= records[[1]]$q250)
stopifnot(records[[1]]$q250 <= records[[1]]$q500)
stopifnot(records[[1]]$q500 <= records[[1]]$q750)
stopifnot(records[[1]]$q750 <= records[[1]]$q975)

observed <- array(
  c(1, NA, 2, 3),
  dim = c(year = 2, age = 2),
  dimnames = list(year = c("2020", "2021"), age = c("younger", "older"))
)
observations <- observation_records(observed, list(
  source = "example", ontology = "example", public_source_ids = list("public-example")
))
stopifnot(length(observations) == 3L)
stopifnot(identical(observations[[1]]$manager_source, "example"))
stopifnot(is.list(observations[[1]]$public_source_ids))
stopifnot(all(vapply(observations, function(x) is.finite(x$value), logical(1))))

mock <- new.env(parent = emptyenv())
mock$get <- function(outcomes, ...) {
  multiplier <- switch(outcomes, numerator_a = 2, numerator_b = 3, denominator = 6)
  array(
    rep(multiplier, 4),
    dim = c(year = 2, sim = 2),
    dimnames = list(year = c("2020", "2021"), sim = c("1", "2"))
  )
}
derived <- get_simulation_array(mock, list(simulation = list(derivation = list(
  operation = "multiply_divide",
  numerator_outcomes = list("numerator_a", "numerator_b"),
  denominator_outcomes = list("denominator")
))), "year")
stopifnot(all(derived == 1))

stopifnot(identical(parse_manager_args(c("a=/one", "b=/two")), c(a = "/one", b = "/two")))
validate_runtime_image(
  paste0("ghcr.io/example/model@sha256:", paste(rep("a", 64), collapse = "")),
  "ghcr.io/example/model"
)
validate_geography("C.12060", "msa")
validate_geography("AL", "state")
stopifnot(identical(
  resolve_observation_locations(NULL, list(observation = list()), "C.12060", "modeled_location"),
  "C.12060"
))

conditional_binding_target <- list(observation = list(location_binding = list(
  state = "modeled_location",
  msa = list(
    default = "nested_likelihood_locations",
    modeled_locations = list("C.33100")
  )
)))
stopifnot(identical(
  resolve_location_binding(conditional_binding_target, "state", "AL"),
  "modeled_location"
))
stopifnot(identical(
  resolve_location_binding(conditional_binding_target, "msa", "C.33100"),
  "modeled_location"
))
stopifnot(identical(
  resolve_location_binding(conditional_binding_target, "msa", "C.12060"),
  "nested_likelihood_locations"
))

cat("calibration exporter pure tests passed\n")
