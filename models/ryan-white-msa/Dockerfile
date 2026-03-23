# =============================================================================
# JHEEM Ryan White MSA Model (31 Cities)
# Thin wrapper around jheem-base - builds workspace, pins jheem2 for runtime
# =============================================================================
ARG BASE_VERSION=1.3.0
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION} AS base

# --- Build workspace (uses base jheem2 1.11.1) ---
FROM base AS workspace-builder

ARG JHEEM_ANALYSES_COMMIT=fc3fe1d2d5f859b322414da8b11f0182e635993b
WORKDIR /app

# Clone jheem_analyses at specific commit
RUN git clone https://github.com/tfojo1/jheem_analyses.git && \
    cd jheem_analyses && git checkout ${JHEEM_ANALYSES_COMMIT}

# Create symlink so ../jheem_analyses paths resolve from /app
RUN ln -s /app/jheem_analyses /jheem_analyses

# Download cached data files from OneDrive using metadata
RUN cd jheem_analyses && mkdir -p cached && \
    R --slave -e "load('commoncode/data_manager_cache_metadata.Rdata'); \
    for(f in names(cache.metadata)) cat('wget -O cached/',f,' \"',cache.metadata[[f]][['onedrive.link']],'\"\n',sep='')" \
    | bash

# Copy google_mobility_data (not in official cache yet)
COPY cached/google_mobility_data.Rdata jheem_analyses/cached/
COPY create_ryan_white_workspace.R ./

# Apply path fixes for container environment
RUN sed -i 's/USE.JHEEM2.PACKAGE = F/USE.JHEEM2.PACKAGE = T/' \
        jheem_analyses/use_jheem2_package_setting.R && \
    sed -i 's|../../cached/ryan.white.data.manager.rdata|../jheem_analyses/cached/ryan.white.data.manager.rdata|' \
        jheem_analyses/applications/ryan_white/ryan_white_specification.R

# Create workspace
RUN Rscript create_ryan_white_workspace.R ryan_white_workspace.RData ../jheem_analyses && \
    test -f ryan_white_workspace.RData

# --- Final image ---
FROM base AS final

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-ryan-white-msa-container"
LABEL org.opencontainers.image.description="JHEEM Ryan White MSA model (31 cities)"

COPY --from=workspace-builder /app/ryan_white_workspace.RData ./

# Pin jheem2 to 1.6.2 for runtime — MSA simsets were calibrated with this version.
# The workspace was built with base's jheem2 (1.11.1) which is fine — workspace is
# just serialized state. Runtime jheem2 must match calibration for correct simulation.
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
