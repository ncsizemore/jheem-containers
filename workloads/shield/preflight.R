analyses.path <- Sys.getenv("JHEEM_ANALYSES_PATH", unset = "")
if (!nzchar(analyses.path)) {
  stop("JHEEM_ANALYSES_PATH is required", call. = FALSE)
}

source(file.path(analyses.path, "applications", "SHIELD", "R", "shield_runtime.R"))
config <- resolve.shield.runtime.config()

profile <- Sys.getenv("SHIELD_CONTAINER_PROFILE", unset = "")
if (!profile %in% c("development", "recorded")) {
  stop("SHIELD_CONTAINER_PROFILE must be development or recorded", call. = FALSE)
}

full.commit <- function(value) grepl("^[0-9a-fA-F]{40}$", value)

if (identical(profile, "recorded")) {
  analyses.ref <- Sys.getenv("JHEEM_ANALYSES_REF", unset = "")
  jheem2.ref <- Sys.getenv("JHEEM2_REF", unset = "")
  if (!full.commit(analyses.ref) || !full.commit(jheem2.ref)) {
    stop("Recorded profile requires full JHEEM_ANALYSES_REF and JHEEM2_REF commits", call. = FALSE)
  }
  if (!identical(config$jheem2_mode, "package")) {
    stop("Recorded profile requires JHEEM2_MODE=package", call. = FALSE)
  }
  if (!isTRUE(config$input_offline) || !isTRUE(config$require_immutable_inputs)) {
    stop(
      "Recorded profile requires offline inputs and immutable input selection",
      call. = FALSE
    )
  }
  if (isTRUE(config$allow_incomplete)) {
    stop("Recorded profile does not permit incomplete assembly", call. = FALSE)
  }
}

required.managers <- c(
  census.manager.rdata = config$census_manager_tag,
  syphilis.manager.rdata = config$syphilis_manager_tag
)
for (manager in names(required.managers)) {
  tag <- required.managers[[manager]]
  if (!is.null(tag)) {
    artifact <- file.path(config$cache_dir, "data-managers", manager, tag, manager)
    metadata <- file.path(dirname(artifact), "resolution.json")
    if (!file.exists(artifact) || !file.exists(metadata)) {
      stop(
        sprintf("JHEEM_CACHE_DIR is missing verified %s release %s", manager, tag),
        call. = FALSE
      )
    }
  }
}

cat(sprintf(
  paste0(
    "SHIELD preflight passed: profile=%s jheem2_mode=%s run_mode=%s ",
    "offline=%s root=%s cache=%s\n"
  ),
  profile,
  config$jheem2_mode,
  config$run_mode,
  config$input_offline,
  config$root_dir,
  config$cache_dir
))
