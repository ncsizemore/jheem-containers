source("calibration/ryan-white/export_calibration.R")

posterior <- array(
  c(1, 3, 5, 7, 9, 2, 4, 6, 8, 10),
  dim = c(year = 2, sim = 5),
  dimnames = list(year = c("2020", "2021"), sim = as.character(1:5))
)
window <- list(from_year = 2020L, to_year = NULL)
records <- posterior_records(posterior, window)
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
), window)
stopifnot(length(observations) == 3L)
stopifnot(identical(observations[[1]]$manager_source, "example"))
stopifnot(is.list(observations[[1]]$public_source_ids))
stopifnot(all(vapply(observations, function(x) is.finite(x$value), logical(1))))

policy_registry <- list(
  policies = list(public_observation_exclusions = list(list(
    policy_id = "lhd-suppression-public-v1",
    source_id = "local-health-department-suppression",
    manager_source = "lhd",
    manager_ontology = "lhd",
    reason = "unresolved_source_identity_and_reuse_terms",
    scope = "public_calibration_artifacts"
  ))),
  sources = list(`local-health-department-suppression` = list()),
  targets = list(clean = list(observation = list(manager_bindings = list(
    msa = list(list(
      source = "cdc.hiv", ontology = "cdc", public_source_ids = list("cdc-nhss-atlasplus")
    ))
  ))))
)
stopifnot(isTRUE(validate_public_observation_policy(policy_registry)))
clean_artifact <- list(targets = list(list(panels = list(list(observations = observations)))))
stopifnot(isTRUE(validate_public_artifact_policy(clean_artifact, policy_registry)))
forbidden_records <- list(
  list(manager_source = "lhd", manager_ontology = "cdc", public_source_ids = list("cdc-nhss-atlasplus")),
  list(manager_source = "cdc.hiv", manager_ontology = "lhd", public_source_ids = list("cdc-nhss-atlasplus")),
  list(
    manager_source = "cdc.hiv", manager_ontology = "cdc",
    public_source_ids = list("local-health-department-suppression")
  )
)
for (forbidden in forbidden_records) {
  artifact <- list(targets = list(list(panels = list(list(observations = list(forbidden))))))
  stopifnot(inherits(try(
    validate_public_artifact_policy(artifact, policy_registry), silent = TRUE
  ), "try-error"))
}
forbidden_registry <- policy_registry
forbidden_registry$targets$clean$observation$manager_bindings$msa[[1]]$source <- "lhd"
stopifnot(inherits(try(
  validate_public_observation_policy(forbidden_registry), silent = TRUE
), "try-error"))
forbidden_registry <- policy_registry
forbidden_registry$targets$clean$observation$source_ids <- list(
  "local-health-department-suppression"
)
stopifnot(inherits(try(
  validate_public_observation_policy(forbidden_registry), silent = TRUE
), "try-error"))

posterior_with_undefined_prefit_values <- posterior
posterior_with_undefined_prefit_values[1, ] <- NaN
fit_records <- posterior_records(
  posterior_with_undefined_prefit_values,
  list(from_year = 2021L, to_year = 2021L)
)
stopifnot(length(fit_records) == 1L, identical(fit_records[[1]]$year, 2021L))
stopifnot(inherits(try(
  posterior_records(posterior_with_undefined_prefit_values, window),
  silent = TRUE
), "try-error"))

stopifnot(identical(
  likelihood_year_window(list(likelihood = list(from_year = 2008))),
  list(from_year = 2008L, to_year = NULL)
))
stopifnot(identical(
  likelihood_year_window(list(likelihood = list(from_year = 2017, to_year = 2021))),
  list(from_year = 2017L, to_year = 2021L)
))
open_window_record <- likelihood_year_window_record(window)
stopifnot(
  is.integer(open_window_record$to_year),
  length(open_window_record$to_year) == 1L,
  is.na(open_window_record$to_year)
)

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

registry_path <- tempfile(fileext = ".yml")
writeLines("registry_id: test", registry_path)
coverage_path <- tempfile(fileext = ".json")
jsonlite::write_json(list(
  schema_version = "jheem-calibration-observation-coverage/v1",
  registry_sha256 = sha256_file(registry_path),
  model = "model",
  records = list(
    list(
      model = "model", stage = "ehe", location = "AL", target_id = "available",
      status = "available", observation_count = 1L
    ),
    list(
      model = "model", stage = "ehe", location = "AL", target_id = "missing",
      status = "unavailable", observation_count = 0L,
      reason = "no_finite_observations_in_likelihood_window"
    )
  )
), coverage_path, auto_unbox = TRUE)
coverage_records <- load_coverage_lock(
  coverage_path, registry_path, "model", "ehe", "AL", c("available", "missing")
)
stopifnot(identical(names(coverage_records), c("available", "missing")))
stopifnot(identical(coverage_records$missing$status, "unavailable"))

unlink(c(registry_path, coverage_path))

cat("calibration exporter pure tests passed\n")
