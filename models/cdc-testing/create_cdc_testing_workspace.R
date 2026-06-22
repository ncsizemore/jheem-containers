# create_cdc_testing_workspace.R - CDC Testing model workspace creation
# Usage: Rscript create_cdc_testing_workspace.R <output_file> [jheem_analyses_path]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript create_cdc_testing_workspace.R <output_file> [jheem_analyses_path]", call. = FALSE)
}
output_file <- args[1]
jheem_analyses_path <- if (length(args) >= 2) args[2] else "../jheem_analyses"

cat("Starting CDC Testing workspace creation\n")
cat("Output file:", output_file, "\n")
cat("jheem_analyses path:", jheem_analyses_path, "\n")
cat("Working directory:", getwd(), "\n")

start_time <- Sys.time()

# Verify jheem_analyses directory exists
if (!dir.exists(jheem_analyses_path)) {
  cat("ERROR: jheem_analyses not found at:", jheem_analyses_path, "\n")
  quit(status = 1)
}

cat("Directory verified:", jheem_analyses_path, "\n")

# 1. Load jheem2 and export internal functions
cat("Loading jheem2 package...\n")
library(jheem2)
cat("jheem2 version:", as.character(packageVersion("jheem2")), "\n")

cat("Exporting jheem2 internal functions...\n")
pkg_env <- asNamespace("jheem2")
internal_fns <- ls(pkg_env, all.names = TRUE)
functions_exported_count <- 0

for (fn_name in internal_fns) {
  if (exists(fn_name, pkg_env, inherits = FALSE)) {
    fn_obj <- get(fn_name, pkg_env, inherits = FALSE)
    if (is.function(fn_obj)) {
      assign(fn_name, fn_obj, envir = .GlobalEnv)
      functions_exported_count <- functions_exported_count + 1
    }
  }
}
cat(functions_exported_count, "internal functions exported to .GlobalEnv\n")

# 2. Source cdc_testing_main.R — the research code's own initialization sequence.
# This sources specification, parameters, likelihood, and interventions in the
# correct order with the right variables set (anchor year, intervention suffix, etc).
# Sourcing main.R instead of cherry-picking individual files makes us resilient
# to changes in the research code's initialization dependencies.
cat("Loading CDC Testing model via cdc_testing_main.R...\n")
cdc_testing_main_file <- file.path(jheem_analyses_path, "applications/cdc_testing/cdc_testing_main.R")

# main.R uses relative paths (e.g., source('applications/cdc_testing/...'))
# so we need to run from the jheem_analyses directory
original_wd <- getwd()
setwd(jheem_analyses_path)
cat("  Working directory for sourcing:", getwd(), "\n")

tryCatch(
  {
    source(cdc_testing_main_file)
    cat("CDC Testing model loaded successfully\n")
    cat("  Anchor year:", CDC.TESTING.ANCHOR.YEAR, "\n")
    cat("  Locations:", length(CDC.TESTING.LOCATIONS), "\n")
    cat("  Intervention codes:", paste(CDC.TESTING.INTERVENTION.CODES, collapse = ", "), "\n")
  },
  error = function(e) {
    cat("ERROR loading CDC Testing model:", e$message, "\n")
    setwd(original_wd)
    quit(status = 1)
  }
)

setwd(original_wd)
cat("  Restored working directory:", getwd(), "\n")

# Load web data manager for container use
# CDC Testing uses the same data manager as Ryan White (EHE-based)
web_dm_path <- file.path(jheem_analyses_path, "cached/ryan.white.web.data.manager.rdata")
cat("Loading web data manager for container use...\n")
tryCatch(
  {
    WEB.DATA.MANAGER <- load.data.manager(web_dm_path, set.as.default = TRUE)
    cat("Web data manager loaded\n")
  },
  error = function(e) {
    cat("ERROR loading web data manager:", e$message, "\n")
    cat("Container may have limited functionality\n")
  }
)

# 4. Verify key objects are available
cat("Verifying key objects...\n")
required_objects <- c("CDCT.SPECIFICATION")
missing_objects <- c()

for (obj_name in required_objects) {
  if (exists(obj_name, envir = .GlobalEnv)) {
    cat(obj_name, "available\n")
  } else {
    cat(obj_name, "MISSING\n")
    missing_objects <- c(missing_objects, obj_name)
  }
}

if (length(missing_objects) > 0) {
  cat("FATAL: Missing required objects:", paste(missing_objects, collapse = ", "), "\n")
  quit(status = 1)
}

# 4.5 Capture VERSION.MANAGER and ONTOLOGY.MAPPING.MANAGER state after registration
cat("\nCapturing JHEEM2 internal state...\n")

# Get VERSION.MANAGER
vm <- asNamespace("jheem2")$VERSION.MANAGER

if (!is.environment(vm)) {
  stop("VERSION.MANAGER is not an environment")
}

# Verify 'cdct' is registered (CDC Testing version)
if (!("versions" %in% ls(vm, all.names = TRUE) && "cdct" %in% vm$versions)) {
  stop("'cdct' version not found in VERSION.MANAGER")
}

cat("  'cdct' version is registered\n")

# Get ONTOLOGY.MAPPING.MANAGER
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
cat("  Ontology mappings found:", length(ont_mgr$mappings), "\n")
if (length(ont_mgr$mappings) > 0) {
  cat("  Mapping names:", paste(names(ont_mgr$mappings), collapse = ", "), "\n")
}

# Create the hidden object with both states using consistent approach
.jheem2_state <- list(
  version_manager = as.list(vm),
  ontology_mapping_manager = as.list(ont_mgr),
  captured_at = Sys.time(),
  jheem2_version = packageVersion("jheem2")
)

# Save to global environment
assign(".jheem2_state", .jheem2_state, envir = .GlobalEnv)

cat("  Internal state captured in .jheem2_state\n")
cat("  Captured", length(.jheem2_state$version_manager), "VERSION.MANAGER elements\n")
cat("  Captured", length(.jheem2_state$ontology_mapping_manager), "ONTOLOGY.MAPPING.MANAGER elements\n")
if ("mappings" %in% names(.jheem2_state$ontology_mapping_manager)) {
  cat("  Including", length(.jheem2_state$ontology_mapping_manager$mappings), "ontology mappings\n")
}

# 5. Save workspace to the path provided by the command line argument
cat("Saving workspace to", output_file, "...\n")
file_size_mb <- NA

tryCatch(
  {
    save.image(file = output_file)

    file_size <- file.info(output_file)$size
    file_size_mb <- round(file_size / 1024^2, 2)
    cat("Workspace saved successfully\n")
    cat("File size:", file_size_mb, "MB\n")
  },
  error = function(e) {
    cat("ERROR saving workspace:", e$message, "\n")
    quit(status = 1)
  }
)

# 6. Final summary
end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units = "secs"))
current_objects <- ls(envir = .GlobalEnv)

cat("\nCDC Testing workspace creation complete!\n")
cat("Total time:", round(total_time, 2), "seconds\n")
cat("Output file:", output_file, "\n")
cat("File size:", file_size_mb, "MB\n")
cat("Objects included:", length(current_objects), "\n")
cat("Anchor year:", CDC.TESTING.ANCHOR.YEAR, "\n")
cat("Ready for container deployment\n")
