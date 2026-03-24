# =============================================================================
# JHEEM Ryan White MSA Model (31 Cities)
# Thin wrapper around jheem-base - prebuilt workspace, pins jheem2 for runtime
# =============================================================================
# MSA is a frozen, published analysis. The workspace and runtime jheem2 must both
# be compatible with jheem2 1.6.2 (the version MSA simsets were calibrated with).
# The workspace is copied from the original container (v2.1.0, built with jheem2
# 1.9.2) which serialized function definitions compatible with 1.6.2's R6 classes.
# Building from source with newer jheem2 would serialize incompatible functions.
# =============================================================================
ARG BASE_VERSION=1.3.0
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION} AS base

# --- Workspace source (prebuilt, jheem2 1.9.2 compatible with 1.6.2 runtime) ---
FROM ghcr.io/ncsizemore/jheem-ryan-white-model:2.1.0 AS workspace-source

# --- Final image ---
FROM base AS final

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-ryan-white-msa-container"
LABEL org.opencontainers.image.description="JHEEM Ryan White MSA model (31 cities)"

COPY --from=workspace-source /app/ryan_white_workspace.RData ./

# Pin jheem2 to 1.6.2 for runtime — MSA simsets were calibrated with this version.
# Workspace functions (from 1.9.2) are compatible with 1.6.2's R6 class signatures.
RUN R -e "renv::install('tfojo1/jheem2@54f669a139281f25cd87dfd0c25a01aca797777c')" && \
    R -e "cat('jheem2 runtime version:', as.character(packageVersion('jheem2')), '\n')"

# Verify workspace
RUN R --slave -e "load('ryan_white_workspace.RData'); \
    cat('Objects:', length(ls()), '\n'); \
    stopifnot(exists('RW.SPECIFICATION')); \
    stopifnot(exists('RW.DATA.MANAGER')); \
    cat('Workspace verified\n')"

ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["batch"]
