# R startup profile for SHIELD runs that use a captured jheem2 build. renv
# ignores R_LIBS, so activate the image's project library as usual, then put
# the run's engine build first. Every R process in the run reads this file and
# stops if the build doesn't match the declared engine commit (JHEEM2_REF).
local({
    if (file.exists("/app/.Rprofile")) {
        working <- setwd("/app")
        on.exit(setwd(working), add = TRUE)
        source("/app/.Rprofile")
    }
})
local({
    refuse <- function(message) {
        cat("SHIELD engine check failed: ", message, "\n", sep = "", file = stderr())
        quit(save = "no", status = 70)
    }
    library.path <- Sys.getenv("SHIELD_ENGINE_LIBRARY")
    expected <- Sys.getenv("JHEEM2_REF")
    marker <- file.path(library.path, "jheem2", "SHIELD-ENGINE.txt")
    if (!nzchar(library.path) || !nzchar(expected) || !file.exists(marker)) {
        refuse("no captured jheem2 build is mounted")
    }
    recorded <- unname(read.dcf(marker, fields = "engine_commit")[1, 1])
    if (!identical(recorded, expected)) {
        refuse(paste0("the mounted build is jheem2 ", recorded, ", not ", expected))
    }
    .libPaths(c(library.path, .libPaths()))
    if (!identical(normalizePath(find.package("jheem2")),
                   normalizePath(file.path(library.path, "jheem2")))) {
        refuse("jheem2 does not resolve to the captured build")
    }
})
