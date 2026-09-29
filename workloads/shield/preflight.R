# Container preflight for the recorded SHIELD path. Configuration rules live in
# jheem_analyses (applications/SHIELD/R/shield_recorded_runtime.R); this checks
# the container-specific contract before any model code is loaded.
analyses.path <- Sys.getenv("JHEEM_ANALYSES_PATH", unset = "")
if (!nzchar(analyses.path)) {
  stop("JHEEM_ANALYSES_PATH is required", call. = FALSE)
}

profile <- Sys.getenv("SHIELD_CONTAINER_PROFILE", unset = "")
if (!profile %in% c("development", "recorded")) {
  stop("SHIELD_CONTAINER_PROFILE must be development or recorded", call. = FALSE)
}

if (identical(profile, "recorded")) {
  if (!identical(tolower(Sys.getenv("SHIELD_RECORDED_RUN")), "true")) {
    stop("Recorded profile requires SHIELD_RECORDED_RUN=true", call. = FALSE)
  }
  source(file.path(analyses.path, "applications", "SHIELD", "R", "shield_recorded_runtime.R"))
  # Validates full source revisions, immutable dated manager tags, separate
  # cache and state trees, run mode, and seed.
  config <- shield.recorded.config()
  if (!identical(config$jheem2_mode, "package")) {
    stop("Recorded profile requires JHEEM2_MODE=package", call. = FALSE)
  }

  sha256 <- function(path) {
    connection <- file(path, open = "rb")
    on.exit(close(connection))
    as.character(openssl::sha256(connection))
  }
  required.managers <- c(census.manager.rdata = config$census_tag,
                         syphilis.manager.rdata = config$syphilis_tag)
  for (manager in names(required.managers)) {
    tag <- required.managers[[manager]]
    artifact <- file.path(config$cache_dir, "data-managers", manager, tag, manager)
    metadata <- file.path(dirname(artifact), "resolution.json")
    if (!file.exists(artifact) || !file.exists(metadata)) {
      stop(sprintf("JHEEM_CACHE_DIR is missing verified %s release %s", manager, tag),
           call. = FALSE)
    }
    expected <- jsonlite::fromJSON(metadata)$sha256
    if (!identical(tolower(sha256(artifact)), tolower(expected))) {
      stop(sprintf("Cached %s release %s fails SHA-256 verification", manager, tag),
           call. = FALSE)
    }
  }

  cat(sprintf(
    "SHIELD preflight passed: profile=recorded run_mode=%s analyses=%s jheem2=%s census=%s syphilis=%s\n",
    config$run_mode, substr(config$analyses_ref, 1, 8), substr(config$jheem2_ref, 1, 8),
    config$census_tag, config$syphilis_tag))
} else {
  cat("SHIELD preflight passed: profile=development (ordinary SHIELD path)\n")
}
