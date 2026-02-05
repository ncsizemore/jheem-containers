# create_cdc_testing_workspace.R - CDC Testing model workspace creation
# Runs from subdirectory where ../jheem_analyses/ naturally exists

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript create_cdc_testing_workspace.R <output_workspace_file.RData>", call. = FALSE)
}
output_file <- args[1]

cat("🔧 Starting CDC Testing workspace creation\n")
cat("📁 Output file:", output_file, "\n")
cat("📁 Working directory:", getwd(), "\n")

start_time <- Sys.time()

# Verify we're in the expected directory structure
if (!dir.exists("../jheem_analyses")) {
  cat("❌ Expected directory structure not found\n")
  cat("📁 Current directory:", getwd(), "\n")
  cat("🔍 Looking for: ../jheem_analyses/\n")
  cat("💡 This script should run from a subdirectory with jheem_analyses/ at parent level\n")
  quit(status = 1)
}

cat("✅ Directory structure verified: ../jheem_analyses/ found\n")

# 1. Load jheem2 and export internal functions
cat("📦 Loading jheem2 package...\n")
library(jheem2)
cat("✅ jheem2 version:", as.character(packageVersion("jheem2")), "\n")

cat("🔓 Exporting jheem2 internal functions...\n")
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
cat("✅", functions_exported_count, "internal functions exported to .GlobalEnv\n")

# 2. Set CDC Testing anchor year BEFORE sourcing interventions
# This controls the intervention suffix (empty for 2025, ".26" for 2026)
# Our release uses non-suffixed files, so we use 2025
CDC.TESTING.ANCHOR.YEAR <- 2025
cat("📅 CDC Testing anchor year set to:", CDC.TESTING.ANCHOR.YEAR, "\n")

# 3. Source CDC Testing model specification
cat("🧬 Loading CDC Testing model specification...\n")
tryCatch(
  {
    source("../jheem_analyses/applications/cdc_testing/cdc_testing_specification.R")
    cat("✅ CDC Testing specification loaded successfully\n")
  },
  error = function(e) {
    cat("❌ ERROR loading specification:", e$message, "\n")
    quit(status = 1)
  }
)

# 3.5. Load CDC Testing interventions
cat("🔧 Loading CDC Testing interventions...\n")
tryCatch(
  {
    source("../jheem_analyses/applications/cdc_testing/cdc_testing_interventions.R")
    cat("✅ CDC Testing interventions loaded successfully\n")
  },
  error = function(e) {
    cat("❌ ERROR loading interventions:", e$message, "\n")
    quit(status = 1)
  }
)

# 3.6. Load web data manager for container use
# CDC Testing uses the same data manager as Ryan White (EHE-based)
cat("🌐 Loading web data manager for container use...\n")
tryCatch(
  {
    WEB.DATA.MANAGER <- load.data.manager("../jheem_analyses/cached/ryan.white.web.data.manager.rdata", set.as.default = TRUE)
    cat("✅ Web data manager loaded\n")
  },
  error = function(e) {
    cat("❌ ERROR loading web data manager:", e$message, "\n")
    cat("⚠️  Container may have limited functionality\n")
  }
)

# 4. Verify key objects are available
cat("🔍 Verifying key objects...\n")
required_objects <- c("CDCT.SPECIFICATION")
missing_objects <- c()

for (obj_name in required_objects) {
  if (exists(obj_name, envir = .GlobalEnv)) {
    cat("✅", obj_name, "available\n")
  } else {
    cat("❌", obj_name, "MISSING\n")
    missing_objects <- c(missing_objects, obj_name)
  }
}

if (length(missing_objects) > 0) {
  cat("❌ FATAL: Missing required objects:", paste(missing_objects, collapse = ", "), "\n")
  quit(status = 1)
}

# 4.5 Capture VERSION.MANAGER and ONTOLOGY.MAPPING.MANAGER state after registration
cat("\n📦 Capturing JHEEM2 internal state...\n")

# Get VERSION.MANAGER
vm <- asNamespace("jheem2")$VERSION.MANAGER

if (!is.environment(vm)) {
  stop("VERSION.MANAGER is not an environment")
}

# Verify 'cdct' is registered (CDC Testing version)
if (!("versions" %in% ls(vm, all.names = TRUE) && "cdct" %in% vm$versions)) {
  stop("'cdct' version not found in VERSION.MANAGER")
}

cat("  ✅ 'cdct' version is registered\n")

# Get ONTOLOGY.MAPPING.MANAGER
ont_mgr <- get("ONTOLOGY.MAPPING.MANAGER", envir = asNamespace("jheem2"))
cat("  📊 Ontology mappings found:", length(ont_mgr$mappings), "\n")
if (length(ont_mgr$mappings) > 0) {
  cat("  🔍 Mapping names:", paste(names(ont_mgr$mappings), collapse = ", "), "\n")
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

cat("  ✅ Internal state captured in .jheem2_state\n")
cat("  📊 Captured", length(.jheem2_state$version_manager), "VERSION.MANAGER elements\n")
cat("  📊 Captured", length(.jheem2_state$ontology_mapping_manager), "ONTOLOGY.MAPPING.MANAGER elements\n")
if ("mappings" %in% names(.jheem2_state$ontology_mapping_manager)) {
  cat("  📊 Including", length(.jheem2_state$ontology_mapping_manager$mappings), "ontology mappings\n")
}

# 5. Save workspace to the path provided by the command line argument
cat("💾 Saving workspace to", output_file, "...\n")
file_size_mb <- NA

tryCatch(
  {
    save.image(file = output_file)

    file_size <- file.info(output_file)$size
    file_size_mb <- round(file_size / 1024^2, 2)
    cat("✅ Workspace saved successfully\n")
    cat("📊 File size:", file_size_mb, "MB\n")
  },
  error = function(e) {
    cat("❌ ERROR saving workspace:", e$message, "\n")
    quit(status = 1)
  }
)

# 6. Final summary
end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units = "secs"))
current_objects <- ls(envir = .GlobalEnv)

cat("\n🎯 CDC Testing workspace creation complete!\n")
cat("⏱️  Total time:", round(total_time, 2), "seconds\n")
cat("📁 Output file:", output_file, "\n")
cat("📊 File size:", file_size_mb, "MB\n")
cat("🔧 Objects included:", length(current_objects), "\n")
cat("📅 Anchor year:", CDC.TESTING.ANCHOR.YEAR, "\n")
cat("✅ Ready for container deployment\n")
