# =============================================================================
# JHEEM CDC Testing Model
# Thin wrapper around jheem-base - only adds workspace creation
# =============================================================================
ARG BASE_VERSION=1.0.0
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION} AS base

# --- Build workspace ---
FROM base AS workspace-builder

ARG JHEEM_ANALYSES_COMMIT=fc3fe1d2d5f859b322414da8b11f0182e635993b
WORKDIR /app

# Clone jheem_analyses at specific commit
RUN git clone https://github.com/tfojo1/jheem_analyses.git && \
    cd jheem_analyses && git checkout ${JHEEM_ANALYSES_COMMIT}

# Create symlink so ../jheem_analyses paths resolve from /app
# This handles all the relative path assumptions in jheem_analyses code
RUN ln -s /app/jheem_analyses /jheem_analyses

# Case-insensitive symlink for EHE directory (Windows dev wrote lowercase paths)
RUN ln -s EHE /app/jheem_analyses/applications/ehe

# Download cached data files from OneDrive using metadata
RUN cd jheem_analyses && mkdir -p cached && \
    R --slave -e "load('commoncode/data_manager_cache_metadata.Rdata'); \
    for(f in names(cache.metadata)) cat('wget -O cached/',f,' \"',cache.metadata[[f]][['onedrive.link']],'\"\n',sep='')" \
    | bash

# Copy google_mobility_data (not in official cache yet)
COPY cached/google_mobility_data.Rdata jheem_analyses/cached/
COPY create_cdc_testing_workspace.R ./

# Apply path fixes for container environment
RUN sed -i 's/USE.JHEEM2.PACKAGE = F/USE.JHEEM2.PACKAGE = T/' \
        jheem_analyses/use_jheem2_package_setting.R

# Create workspace - run from /app, use ../jheem_analyses (via symlink)
RUN Rscript create_cdc_testing_workspace.R cdc_testing_workspace.RData ../jheem_analyses && \
    test -f cdc_testing_workspace.RData

# --- Final image ---
FROM base AS final

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-cdc-testing-container"
LABEL org.opencontainers.image.description="JHEEM CDC Testing model container"

COPY --from=workspace-builder /app/cdc_testing_workspace.RData ./

# Verify workspace
RUN R --slave -e "load('cdc_testing_workspace.RData'); \
    cat('Objects:', length(ls()), '\n'); \
    stopifnot(exists('CDCT.SPECIFICATION')); \
    cat('Workspace verified\n')"

EXPOSE 8080
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["lambda"]
