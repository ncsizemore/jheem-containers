# =============================================================================
# JHEEM CDC Testing Model
# Thin wrapper around jheem-base - adds workspace creation + simulation script
# =============================================================================
# Updated from fc3fe1d to include proportion.tested.regardless model element
ARG BASE_VERSION=1.6.4
ARG JHEEM_ANALYSES_COMMIT=51ac4957
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION}@sha256:b104358d399443031b66cd5abf7e660ae9c465a1b7dbd5dc2a72756581c32ca1 AS base

# jheem2 1.11.1 inherited from base (no override needed)

# --- Build workspace ---
FROM base AS workspace-builder

ARG JHEEM_ANALYSES_COMMIT

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

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-containers"
LABEL org.opencontainers.image.description="JHEEM CDC Testing model container"

COPY --from=workspace-builder /app/cdc_testing_workspace.RData ./

# CDC Testing custom simulation script
COPY simple_cdc_testing.R simulation/simple_cdc_testing.R

# Verify workspace
RUN R --slave -e "load('cdc_testing_workspace.RData'); \
    cat('Objects:', length(ls()), '\n'); \
    stopifnot(exists('CDCT.SPECIFICATION')); \
    cat('Workspace verified\n')"

# --- Self-describing identity & provenance ---
# jheem2 inherited from base (not pinned per-model); no workspace skew (built and
# run with the same jheem2). Base simset is the no-intervention scenario (_noint).
# Data is OneDrive-sourced at build time, not yet release-pinned (see jheem-portal
# REPRODUCIBILITY-AND-CITATION-PLAN §5d).
ARG BASE_VERSION
ARG JHEEM_ANALYSES_COMMIT
ENV MODEL_ID=cdc-testing \
    SIMULATION_SCRIPT=simple_cdc_testing.R \
    DEFAULT_OUTCOMES=incidence \
    PARAM_ENV_MAP="testing_reduction=TESTING_REDUCTION proportion_tested_regardless=PROPORTION_TESTED" \
    SIMSET_RELEASE=cdc-testing-v1.0.0 \
    SIMSET_BASE_SUFFIX=_noint \
    JHEEM_ANALYSES_REF=${JHEEM_ANALYSES_COMMIT} \
    JHEEM_BASE_VERSION=${BASE_VERSION}

EXPOSE 8080
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["version"]
