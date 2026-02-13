# =============================================================================
# JHEEM Ryan White CROI Model (30 States, 2026-2031)
# Thin wrapper around jheem-base - only adds workspace creation
# =============================================================================
ARG BASE_VERSION=1.0.0
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION} AS base

# CROI requires jheem2 dev branch (not the renv.lock version)
RUN R -e "renv::install('tfojo1/jheem2@dev')" && \
    R -e "cat('jheem2 version:', as.character(packageVersion('jheem2')), '\n')"

# --- Build workspace ---
FROM base AS workspace-builder

# CROI uses latest HEAD (pin to specific commit once published)
ARG JHEEM_ANALYSES_COMMIT=HEAD
WORKDIR /app

# Clone jheem_analyses
RUN git clone https://github.com/tfojo1/jheem_analyses.git && \
    cd jheem_analyses && \
    if [ "${JHEEM_ANALYSES_COMMIT}" != "HEAD" ]; then \
      git checkout ${JHEEM_ANALYSES_COMMIT}; \
    fi && \
    echo "jheem_analyses at $(git rev-parse --short HEAD)"

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

# Create workspace - run from /app, use ../jheem_analyses (via symlink)
RUN Rscript create_ryan_white_workspace.R ryan_white_workspace.RData ../jheem_analyses && \
    test -f ryan_white_workspace.RData

# --- Final image ---
FROM base AS final

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-ryan-white-croi-container"
LABEL org.opencontainers.image.description="JHEEM Ryan White CROI model (30 states, 2026-2031)"

COPY --from=workspace-builder /app/ryan_white_workspace.RData ./

# CROI needs additional runtime data directories for simulation operations
# The cache lookup uses path '../jheem_analyses/...' relative to /app
COPY --from=workspace-builder /app/jheem_analyses/commoncode/object_for_version_cache /jheem_analyses/commoncode/object_for_version_cache
COPY --from=workspace-builder /app/jheem_analyses/data_files /jheem_analyses/data_files
COPY --from=workspace-builder /app/jheem_analyses/cached /jheem_analyses/cached

# CROI-specific: trim_simsets.R for processing large simulation files
COPY trim_simsets.R ./

# Verify workspace
RUN R --slave -e "load('ryan_white_workspace.RData'); \
    cat('Objects:', length(ls()), '\n'); \
    stopifnot(exists('RW.SPECIFICATION')); \
    stopifnot(exists('RW.DATA.MANAGER')); \
    cat('Workspace verified\n')"

EXPOSE 8080
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["lambda"]
