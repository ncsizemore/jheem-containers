#!/usr/bin/env Rscript

# Lightweight preflight for location-specific calibration observation coverage.
# This intentionally does not load simulation sets or compute posterior summaries.

coverage_script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) != 1L) stop("could not resolve coverage script path", call. = FALSE)
  normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
}

source(file.path(dirname(coverage_script_path()), "export_calibration.R"))

parse_coverage_cli <- function(args) {
  result <- list(manager = character())
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) fail("unexpected argument: ", key)
    if (i == length(args)) fail("missing value for ", key)
    value <- args[[i + 1L]]
    name <- sub("^--", "", key)
    if (name == "manager") result$manager <- c(result$manager, value) else result[[name]] <- value
    i <- i + 2L
  }
  required <- c("registry", "model", "locations", "output")
  missing <- required[!vapply(required, function(x) !is.null(result[[x]]), logical(1))]
  if (length(missing)) fail("missing required arguments: --", paste(missing, collapse = ", --"))
  result
}

load_managers <- function(registry, manager_paths, required_manager_ids) {
  if (!setequal(required_manager_ids, names(manager_paths))) {
    fail("--manager IDs must exactly match required managers: ", paste(sort(required_manager_ids), collapse = ", "))
  }
  managers <- list()
  for (manager_id in sort(required_manager_ids)) {
    path <- manager_paths[[manager_id]]
    expected_hash <- registry$data_managers[[manager_id]]$sha256
    actual_hash <- sha256_file(path)
    if (!identical(actual_hash, expected_hash)) fail("manager SHA-256 mismatch for ", manager_id)
    managers[[manager_id]] <- load_single_object(
      path, function(x) inherits(x, "jheem.data.manager"), "jheem.data.manager"
    )
  }
  managers
}

get_unmapped_observation_array <- function(manager, target, binding, keep_dimensions, location,
                                           location_binding) {
  observation_locations <- resolve_observation_locations(manager, target, location, location_binding)
  manager$pull(
    outcome = target$observation$outcome,
    metric = "estimate",
    sources = binding$source,
    from.ontology.names = binding$ontology,
    keep.dimensions = unique(c(keep_dimensions, "location")),
    dimension.values = list(location = observation_locations),
    na.rm = TRUE
  )
}

coverage_record <- function(model_id, stage_id, geography, location, target_id, target, managers) {
  location_binding <- tryCatch(
    resolve_location_binding(target, geography, location),
    error = function(error) error
  )
  base <- list(
    model = model_id,
    stage = stage_id,
    location = location,
    target_id = target_id,
    public_panel = target$public_panel,
    observation_location_binding = if (inherits(location_binding, "error")) NA_character_ else location_binding
  )
  if (inherits(location_binding, "error")) {
    return(c(base, list(
      status = "error",
      observation_count = 0L,
      reason = conditionMessage(location_binding)
    )))
  }
  if (identical(target$public_panel, "not_exported")) {
    return(c(base, list(status = "not_exported", observation_count = 0L)))
  }

  bindings <- target$observation$manager_bindings[[geography]]
  if (is.null(bindings) || !length(bindings)) fail("target ", target_id, " has no manager bindings for ", geography)
  manager <- managers[[target$observation$manager]]
  window <- likelihood_year_window(target)
  observations <- tryCatch(
    unlist(lapply(bindings, function(binding) {
      observation_records(
        get_unmapped_observation_array(
          manager, target, binding, "year", location, location_binding
        ),
        binding,
        window
      )
    }), recursive = FALSE),
    error = function(error) error
  )
  if (inherits(observations, "error")) {
    message <- conditionMessage(observations)
    missing_selection_outcome <- grepl(
      "Cannot pull '.+' data from the data manager: '.+' is not a registered outcome\\.$",
      message
    )
    return(c(base, list(
      status = if (missing_selection_outcome) "unavailable" else "error",
      observation_count = 0L,
      reason = if (missing_selection_outcome) {
        "selection_outcome_not_in_archived_manager"
      } else {
        "unexpected_observation_resolution_error"
      },
      detail = message
    )))
  }
  c(base, list(
    status = if (length(observations)) "available" else "unavailable",
    observation_count = length(observations),
    reason = if (length(observations)) NA_character_ else "no_finite_observations_in_likelihood_window"
  ))
}

inspect_coverage <- function(registry, model_id, locations, managers) {
  model <- registry$models[[model_id]]
  if (is.null(model)) fail("unknown registry model: ", model_id)
  records <- list()
  for (stage_id in names(model$stages)) {
    stage <- model$stages[[stage_id]]
    target_ids <- unname(unlist(registry$target_sets[[stage$target_set]]$target_ids))
    for (location in sort(unique(locations))) {
      for (target_id in target_ids) {
        records[[length(records) + 1L]] <- coverage_record(
          model_id, stage_id, model$geography, location, target_id,
          registry$targets[[target_id]], managers
        )
      }
    }
  }
  records
}

coverage_main <- function() {
  suppressPackageStartupMessages({
    library(jheem2)
    if (!requireNamespace("yaml", quietly = TRUE)) fail("R package yaml is required")
    if (!requireNamespace("jsonlite", quietly = TRUE)) fail("R package jsonlite is required")
  })
  args <- parse_coverage_cli(commandArgs(trailingOnly = TRUE))
  registry <- yaml::read_yaml(args$registry)
  model <- registry$models[[args$model]]
  if (is.null(model)) fail("unknown registry model: ", args$model)
  target_ids <- unique(unlist(lapply(model$stages, function(stage) {
    registry$target_sets[[stage$target_set]]$target_ids
  })))
  required_manager_ids <- unique(vapply(target_ids, function(id) {
    registry$targets[[id]]$observation$manager
  }, character(1)))
  managers <- load_managers(registry, parse_manager_args(args$manager), required_manager_ids)
  locations <- trimws(strsplit(args$locations, ",", fixed = TRUE)[[1]])
  if (!length(locations) || any(!nzchar(locations))) fail("--locations must be a comma-separated non-empty list")
  records <- inspect_coverage(registry, args$model, locations, managers)
  output <- list(
    schema_version = "jheem-calibration-observation-coverage/v1",
    registry_id = registry$registry_id,
    registry_sha256 = sha256_file(args$registry),
    model = args$model,
    locations = as.list(sort(unique(locations))),
    records = records
  )
  dir.create(dirname(args$output), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(output, args$output, auto_unbox = TRUE, pretty = TRUE, digits = 15)
  cat(sha256_file(args$output), "  ", basename(args$output), "\n", sep = "")
}

if (sys.nframe() == 0L) coverage_main()
