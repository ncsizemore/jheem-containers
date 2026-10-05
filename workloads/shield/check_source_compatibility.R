# Read-only model startup for a separately selected analysis snapshot. This is
# compatibility evidence, not a likelihood review or a scientific acceptance test.
if (!identical(Sys.getenv("SHIELD_RECORDED_RUN"), "true")) {
    stop("Source compatibility check requires recorded mode", call. = FALSE)
}
analyses <- Sys.getenv("JHEEM_ANALYSES_PATH")
source(file.path(analyses, "applications/SHIELD/R/shield_recorded_runtime.R"))
config <- shield.recorded.config()
setwd(analyses)
shield <- file.path(analyses, "applications/SHIELD")
source(file.path(shield, "shield_specification.R"))
source(file.path(shield, "shield_likelihoods.R"))
source(file.path(shield, "shield_calib_register.R"))
if (identical(Sys.getenv("SHIELD_ENABLE_CONTAINER_SMOKE"), "true")) {
    source(file.path(shield, "shield_calib_register_container_smoke.R"))
}
codes <- commandArgs(trailingOnly = TRUE)
if (!length(codes)) stop("No calibration requested", call. = FALSE)
# Code that runs stages in phases (setup, each chain, assembly) takes
# multi-chain stages; older code runs single-chain stages only.
phased <- "allow.multiple.chains" %in% names(formals(shield.recorded.calibration.info))
for (code in codes) {
    if (phased) shield.recorded.calibration.info(code, allow.multiple.chains = TRUE)
    else shield.recorded.calibration.info(code)
}
cat("SHIELD source compatibility passed for:", paste(codes, collapse = ", "), "\n")
