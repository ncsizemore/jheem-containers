#!/usr/bin/env Rscript

QUANTILES <- c(0.025, 0.25, 0.5, 0.75, 0.975)
QUANTILE_NAMES <- c("q025", "q250", "q500", "q750", "q975")

fail <- function(...) stop(paste0(...), call. = FALSE)

sha256_file <- function(path) {
  if (!file.exists(path)) fail("file does not exist: ", path)
  digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
}

current_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) != 1L) fail("could not resolve exporter script path")
  normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
}

parse_cli <- function(args) {
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
  required <- c("registry", "model", "stage", "simset", "simulation-asset-name",
                "simulation-asset-sha256", "workspace", "runtime-image", "output")
  missing <- required[!vapply(required, function(x) !is.null(result[[x]]), logical(1))]
  if (length(missing)) fail("missing required arguments: --", paste(missing, collapse = ", --"))
  result
}

parse_manager_args <- function(values) {
  if (!length(values)) fail("at least one --manager ID=PATH is required")
  parts <- strsplit(values, "=", fixed = TRUE)
  bad <- lengths(parts) != 2L | !nzchar(vapply(parts, `[[`, character(1), 1L)) |
    !nzchar(vapply(parts, `[[`, character(1), 2L))
  if (any(bad)) fail("manager arguments must use ID=PATH")
  ids <- vapply(parts, `[[`, character(1), 1L)
  if (anyDuplicated(ids)) fail("manager IDs must be unique")
  stats::setNames(vapply(parts, `[[`, character(1), 2L), ids)
}

load_single_object <- function(path, predicate, label) {
  env <- new.env(parent = globalenv())
  loaded <- load(path, envir = env)
  matches <- loaded[vapply(loaded, function(name) predicate(env[[name]]), logical(1))]
  if (length(matches) != 1L) fail(path, " must contain exactly one ", label, " object")
  env[[matches[[1]]]]
}

initialize_jheem_runtime <- function(workspace_path) {
  suppressPackageStartupMessages(library(jheem2))

  # Historical serialized simulation objects call package-internal helpers by
  # name. This mirrors the established container execution path and makes the
  # exact runtime dependency explicit instead of relying on ambient globals.
  namespace <- asNamespace("jheem2")
  for (name in ls(namespace, all.names = TRUE)) {
    value <- get(name, envir = namespace, inherits = FALSE)
    if (is.function(value)) assign(name, value, envir = globalenv())
  }

  load(workspace_path, envir = globalenv())
  if (!exists(".jheem2_state", envir = globalenv(), inherits = FALSE)) {
    fail("workspace does not contain required .jheem2_state")
  }
  state <- get(".jheem2_state", envir = globalenv(), inherits = FALSE)
  if (is.null(state$version_manager) || is.null(state$ontology_mapping_manager)) {
    fail("workspace .jheem2_state is incomplete")
  }

  version_manager <- namespace$VERSION.MANAGER
  for (name in names(state$version_manager)) {
    assign(name, state$version_manager[[name]], envir = version_manager)
  }
  ontology_manager <- get("ONTOLOGY.MAPPING.MANAGER", envir = namespace)
  for (name in names(state$ontology_mapping_manager)) {
    assign(name, state$ontology_mapping_manager[[name]], envir = ontology_manager)
  }
}

normalize_location <- function(location) {
  value <- unname(as.character(location))
  if (length(value) != 1L || !nzchar(value)) fail("simset location must be one non-empty value")
  value
}

validate_asset_digest <- function(actual, expected) {
  expected <- tolower(expected)
  if (!grepl("^[0-9a-f]{64}$", expected)) fail("simulation asset SHA-256 is malformed")
  if (!identical(actual, expected)) fail("simulation asset SHA-256 does not match --simulation-asset-sha256")
}

validate_runtime_image <- function(image, expected_repository = NULL) {
  if (!grepl("^ghcr\\.io/.+@sha256:[0-9a-f]{64}$", image)) {
    fail("--runtime-image must be an immutable ghcr.io image digest reference")
  }
  if (!is.null(expected_repository) && !startsWith(image, paste0(expected_repository, "@sha256:"))) {
    fail("runtime image repository does not match registry model")
  }
}

validate_geography <- function(location, geography) {
  valid <- switch(
    geography,
    msa = grepl("^C\\.[0-9]{5}$", location),
    state = grepl("^[A-Z]{2}$", location),
    FALSE
  )
  if (!valid) fail("simset location does not match registry geography")
}

array_to_frame <- function(x) {
  if (!is.array(x)) fail("expected an array from JHEEM extraction")
  if (is.null(names(dimnames(x))) || any(!nzchar(names(dimnames(x))))) {
    fail("every extracted array dimension must be named")
  }
  as.data.frame.table(x, responseName = "value", stringsAsFactors = FALSE)
}

stratum_from_row <- function(row, dimensions) {
  # A named empty list serializes as `{}` rather than `[]`, preserving the
  # schema's object type for total-level points.
  if (!length(dimensions)) return(stats::setNames(list(), character()))
  stats::setNames(as.list(as.character(row[dimensions])), dimensions)
}

likelihood_year_window <- function(target) {
  from_year <- suppressWarnings(as.integer(target$likelihood$from_year))
  if (length(from_year) != 1L || is.na(from_year)) {
    fail("target likelihood must define one integer from_year")
  }
  to_year <- target$likelihood$to_year
  if (is.null(to_year)) {
    to_year <- NULL
  } else {
    to_year <- suppressWarnings(as.integer(to_year))
    if (length(to_year) != 1L || is.na(to_year)) {
      fail("target likelihood to_year must be one integer when present")
    }
    if (to_year < from_year) fail("target likelihood to_year precedes from_year")
  }
  list(from_year = from_year, to_year = to_year)
}

restrict_to_likelihood_years <- function(frame, window) {
  if (!"year" %in% names(frame)) fail("array is missing year")
  years <- suppressWarnings(as.integer(as.character(frame$year)))
  if (anyNA(years)) fail("array contains a non-integer year")
  keep <- years >= window$from_year
  if (!is.null(window$to_year)) keep <- keep & years <= window$to_year
  frame[keep, , drop = FALSE]
}

likelihood_year_window_record <- function(window) {
  list(
    from_year = window$from_year,
    # jsonlite serializes a bare NULL list member as `{}` under auto_unbox.
    # A typed NA is emitted as JSON null by the artifact writer's na policy.
    to_year = if (is.null(window$to_year)) NA_integer_ else window$to_year
  )
}

posterior_records <- function(x, window) {
  frame <- array_to_frame(x)
  sim_dimension <- intersect(c("sim", "simulation"), names(frame))
  if (length(sim_dimension) != 1L) fail("posterior array must contain exactly one simulation dimension")
  frame <- restrict_to_likelihood_years(frame, window)
  if (!nrow(frame)) fail("posterior array has no values in the likelihood year window")
  if (any(!is.finite(frame$value))) fail("posterior array contains non-finite values")
  group_dimensions <- setdiff(names(frame), c(sim_dimension, "value"))
  keys <- interaction(frame[group_dimensions], drop = TRUE, lex.order = TRUE)
  groups <- split(frame, keys)
  records <- lapply(groups, function(group) {
    values <- unname(stats::quantile(group$value, probs = QUANTILES, names = FALSE, type = 7))
    dimensions <- setdiff(group_dimensions, "year")
    c(list(year = as.integer(as.character(group$year[[1]])),
           stratum = stratum_from_row(group[1, , drop = FALSE], dimensions)),
      stats::setNames(as.list(values), QUANTILE_NAMES))
  })
  order_key <- vapply(records, function(x) paste(c(x$year, unlist(x$stratum)), collapse = "\r"), character(1))
  # split() names each group; remove those implementation-only names so
  # jsonlite serializes the records as the schema's array rather than an object.
  unname(records[order(order_key)])
}

observation_records <- function(x, binding, window) {
  if (is.null(x)) return(list())
  frame <- array_to_frame(x)
  frame <- restrict_to_likelihood_years(frame, window)
  frame <- frame[is.finite(frame$value), , drop = FALSE]
  if (!nrow(frame)) return(list())
  dimensions <- setdiff(names(frame), c("year", "source", "value"))
  records <- lapply(seq_len(nrow(frame)), function(i) {
    row <- frame[i, , drop = FALSE]
    list(
      year = as.integer(as.character(row$year[[1]])),
      stratum = stratum_from_row(row, dimensions),
      value = as.numeric(row$value[[1]]),
      manager_source = binding$source,
      manager_ontology = binding$ontology,
      # Keep this as a list so jsonlite never auto-unboxes a single source ID.
      public_source_ids = as.list(unname(unlist(binding$public_source_ids)))
    )
  })
  order_key <- vapply(records, function(x) paste(c(x$year, unlist(x$stratum), x$manager_source), collapse = "\r"), character(1))
  records[order(order_key)]
}

get_simulation_array <- function(simset, target, keep_dimensions) {
  simulation <- target$simulation
  if (is.null(simulation$derivation)) {
    return(simset$get(
      outcomes = simulation$outcome,
      output = "value",
      keep.dimensions = keep_dimensions,
      drop.single.sim.dimension = FALSE,
      replace.inf.values.with.zero = FALSE,
      summary.type = "individual.simulation"
    ))
  }
  derivation <- simulation$derivation
  if (!identical(derivation$operation, "multiply_divide")) fail("unsupported derivation operation")
  numerator <- unname(unlist(derivation$numerator_outcomes))
  denominator <- unname(unlist(derivation$denominator_outcomes))
  get_one <- function(outcome) simset$get(
    outcomes = outcome,
    output = "value",
    keep.dimensions = keep_dimensions,
    drop.single.sim.dimension = FALSE,
    replace.inf.values.with.zero = FALSE,
    summary.type = "individual.simulation"
  )
  arrays <- lapply(c(numerator, denominator), get_one)
  reference <- dimnames(arrays[[1]])
  if (!all(vapply(arrays, function(x) identical(dimnames(x), reference), logical(1)))) {
    fail("derived simulation inputs have incompatible dimensions")
  }
  result <- Reduce(`*`, arrays[seq_along(numerator)])
  if (length(denominator)) result <- result / Reduce(`*`, arrays[length(numerator) + seq_along(denominator)])
  if (any(!is.finite(result))) fail("derived simulation outcome contains non-finite values")
  result
}

resolve_location_binding <- function(target, geography, location) {
  binding <- target$observation$location_binding %||% "modeled_location"
  if (is.character(binding) && length(binding) == 1L) return(binding)
  if (!is.list(binding)) fail("observation location binding must be a string or geography map")

  geography_binding <- binding[[geography]]
  if (is.null(geography_binding)) fail("observation location binding has no rule for ", geography)
  if (is.character(geography_binding) && length(geography_binding) == 1L) return(geography_binding)
  if (!is.list(geography_binding)) fail("observation location binding rule is invalid for ", geography)

  modeled_locations <- unname(unlist(geography_binding$modeled_locations %||% list()))
  if (location %in% modeled_locations) return("modeled_location")
  default <- geography_binding$default
  if (!is.character(default) || length(default) != 1L) {
    fail("observation location binding rule has no valid default for ", geography)
  }
  default
}

resolve_observation_locations <- function(manager, target, location, location_binding) {
  if (identical(location_binding, "modeled_location")) return(location)
  if (!identical(location_binding, "nested_likelihood_locations")) {
    fail("unsupported observation location binding: ", location_binding)
  }

  likelihood <- target$likelihood
  required <- c("denominator_outcome", "location_types", "maximum_locations_per_type",
                "minimum_geographic_resolution_type")
  missing <- required[vapply(required, function(name) is.null(likelihood[[name]]), logical(1))]
  if (length(missing)) fail("nested observation location binding is incomplete: ", paste(missing, collapse = ", "))

  minimum_type <- likelihood$minimum_geographic_resolution_type
  modeled_components <- unname(unlist(locations::get.location.code(
    locations::get.contained.locations(location, minimum_type), minimum_type
  )))
  maximum <- as.integer(likelihood$maximum_locations_per_type)
  select_type <- function(type) {
    candidates <- unname(unlist(locations::get.location.code(
      locations::get.overlapping.locations(location, type), type
    )))
    if (length(candidates) <= maximum) return(candidates)

    weights <- vapply(candidates, function(candidate) {
      candidate_components <- unname(unlist(locations::get.location.code(
        locations::get.contained.locations(candidate, minimum_type), minimum_type
      )))
      overlap <- intersect(candidate_components, modeled_components)
      if (!length(overlap)) return(NA_real_)
      denominator <- manager$pull(
        outcome = likelihood$denominator_outcome,
        keep.dimensions = "year",
        dimension.values = list(location = overlap),
        na.rm = TRUE
      )
      if (is.null(denominator) || !length(denominator)) return(NA_real_)
      mean(denominator, na.rm = TRUE)
    }, numeric(1))
    candidates <- candidates[is.finite(weights)]
    weights <- weights[is.finite(weights)]
    if (!length(candidates)) return(character())
    candidates[order(weights, decreasing = TRUE)][seq_len(min(maximum, length(candidates)))]
  }
  locations <- sort(unique(unlist(lapply(unname(unlist(likelihood$location_types)), select_type))))
  if (!length(locations)) fail("nested observation location binding resolved no locations for ", location)
  locations
}

get_observation_array <- function(manager, simset, target, binding, keep_dimensions, location,
                                  location_binding) {
  ontology_outcome <- target$simulation$ontology_outcome %||% target$simulation$outcome
  target_ontology <- simset$outcome.ontologies[[ontology_outcome]]
  if (is.null(target_ontology)) fail("simset lacks ontology outcome: ", ontology_outcome)
  observation_locations <- resolve_observation_locations(manager, target, location, location_binding)
  manager$pull(
    outcome = target$observation$outcome,
    metric = "estimate",
    sources = binding$source,
    from.ontology.names = binding$ontology,
    keep.dimensions = unique(c(keep_dimensions, "location")),
    dimension.values = list(location = observation_locations),
    target.ontology = target_ontology,
    allow.mapping.from.target.ontology = TRUE,
    na.rm = TRUE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

export_target <- function(target_id, target, geography, simset, managers, location) {
  location_binding <- resolve_location_binding(target, geography, location)
  window <- likelihood_year_window(target)
  if (identical(target$public_panel, "not_exported")) {
    return(list(
      target_id = target_id,
      label = target$label,
      classification = target$classification,
      public_panel = target$public_panel,
      unit = target$simulation$unit,
      likelihood_year_window = likelihood_year_window_record(window),
      observation_provenance_confidence = target$observation$provenance_confidence,
      observation_location_binding = location_binding,
      panels = list()
    ))
  }
  bindings <- target$observation$manager_bindings[[geography]]
  if (is.null(bindings) || !length(bindings)) fail("target ", target_id, " has no manager bindings for ", geography)
  manager <- managers[[target$observation$manager]]
  panels <- lapply(unname(unlist(target$facets)), function(facet) {
    keep <- if (facet == "total") "year" else c("year", facet)
    posterior <- tryCatch(
      posterior_records(get_simulation_array(simset, target, keep), window),
      error = function(error) fail(
        "target ", target_id, " facet ", facet, " posterior: ", conditionMessage(error)
      )
    )
    observations <- tryCatch(
      unlist(lapply(bindings, function(binding) {
        observation_records(get_observation_array(
          manager, simset, target, binding, keep, location, location_binding
        ), binding, window)
      }), recursive = FALSE),
      error = function(error) fail(
        "target ", target_id, " facet ", facet, " observations: ", conditionMessage(error)
      )
    )
    if (facet == "total" && !length(observations)) {
      fail("target ", target_id, " has no total-level observations for ", location)
    }
    list(facet = facet, posterior = posterior, observations = observations)
  })
  list(
    target_id = target_id,
    label = target$label,
    classification = target$classification,
    public_panel = target$public_panel,
    unit = target$simulation$unit,
    likelihood_year_window = likelihood_year_window_record(window),
    observation_provenance_confidence = target$observation$provenance_confidence,
    observation_location_binding = location_binding,
    panels = panels
  )
}

main <- function() {
  suppressPackageStartupMessages({
    if (!requireNamespace("yaml", quietly = TRUE)) fail("R package yaml is required")
    if (!requireNamespace("jsonlite", quietly = TRUE)) fail("R package jsonlite is required")
    if (!requireNamespace("digest", quietly = TRUE)) fail("R package digest is required")
  })
  args <- parse_cli(commandArgs(trailingOnly = TRUE))
  registry <- yaml::read_yaml(args$registry)
  model <- registry$models[[args$model]]
  if (is.null(model)) fail("unknown registry model: ", args$model)
  stage <- model$stages[[args$stage]]
  if (is.null(stage)) fail("unknown stage ", args$stage, " for model ", args$model)
  manager_paths <- parse_manager_args(args$manager)
  validate_runtime_image(args[["runtime-image"]], model$runtime_image_repository)
  if (!identical(basename(args$simset), args[["simulation-asset-name"]])) {
    fail("simulation asset name does not match simset filename")
  }

  initialize_jheem_runtime(args$workspace)
  simset_hash <- sha256_file(args$simset)
  validate_asset_digest(simset_hash, args[["simulation-asset-sha256"]])
  simset <- load_single_object(args$simset, function(x) inherits(x, "jheem.simulation.set"), "jheem.simulation.set")
  location <- normalize_location(simset$location)
  validate_geography(location, model$geography)
  if (!identical(as.integer(simset$n.sim), as.integer(stage$sample_count))) fail("simset sample count does not match registry")
  if (!identical(as.character(simset$calibration.code), as.character(stage$calibration_code))) fail("simset calibration code does not match registry")

  target_set <- registry$target_sets[[stage$target_set]]
  target_ids <- unname(unlist(target_set$target_ids))
  required_manager_ids <- unique(vapply(target_ids, function(id) registry$targets[[id]]$observation$manager, character(1)))
  if (!setequal(required_manager_ids, names(manager_paths))) {
    fail("--manager IDs must exactly match required managers: ", paste(sort(required_manager_ids), collapse = ", "))
  }
  managers <- list()
  manager_sources <- list()
  for (manager_id in sort(required_manager_ids)) {
    path <- manager_paths[[manager_id]]
    expected_hash <- registry$data_managers[[manager_id]]$sha256
    actual_hash <- sha256_file(path)
    if (!identical(actual_hash, expected_hash)) fail("manager SHA-256 mismatch for ", manager_id)
    managers[[manager_id]] <- load_single_object(path, function(x) inherits(x, "jheem.data.manager"), "jheem.data.manager")
    manager_registry <- registry$data_managers[[manager_id]]
    manager_sources[[length(manager_sources) + 1L]] <- list(
      manager_id = manager_id,
      controlled_release = manager_registry$controlled_release,
      filename = manager_registry$asset_filename,
      sha256 = actual_hash
    )
  }

  targets <- lapply(target_ids, function(id) export_target(
    id, registry$targets[[id]], model$geography, simset, managers, location
  ))
  artifact <- list(
    schema_version = "jheem-calibration/v1",
    artifact_id = paste(args$model, args$stage, location, sep = ":"),
    model = args$model,
    stage = args$stage,
    location = location,
    ensemble = list(
      sample_count = as.integer(simset$n.sim),
      kind = stage$ensemble_kind,
      calibration_code = as.character(simset$calibration.code),
      quantiles = as.list(QUANTILES)
    ),
    simulation_source = list(
      release = stage$simulation_release,
      filename = args[["simulation-asset-name"]],
      sha256 = simset_hash
    ),
    runtime_source = list(
      image = args[["runtime-image"]],
      filename = basename(args$workspace),
      sha256 = sha256_file(args$workspace)
    ),
    exporter_source = list(
      filename = basename(current_script_path()),
      sha256 = sha256_file(current_script_path())
    ),
    registry_source = list(
      registry_id = registry$registry_id,
      filename = basename(args$registry),
      sha256 = sha256_file(args$registry)
    ),
    manager_sources = manager_sources,
    targets = targets
  )
  dir.create(dirname(args$output), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(artifact, args$output, auto_unbox = TRUE, pretty = TRUE, digits = 15, na = "null")
  cat(sha256_file(args$output), "  ", basename(args$output), "\n", sep = "")
}

if (sys.nframe() == 0L) main()
