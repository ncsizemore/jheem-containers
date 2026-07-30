# =============================================================================
# JHEEM Ryan White CROI Model (30 States, 2026-2031)
# Thin wrapper around jheem-base - only adds workspace creation
# =============================================================================
ARG BASE_VERSION=1.6.5
# Pinned (was HEAD — a reproducibility hole). 250ffc8a is the jheem_analyses HEAD
# at the deployed image's build (croi v2.2.0, 2026-03-26T18:08Z), traced from the
# build timestamp; rebuild reproduces the production golden bit-for-bit.
ARG JHEEM_ANALYSES_COMMIT=250ffc8aafcabe00c1bca20df831bf9637c2dd12
ARG BASE_IMAGE=ghcr.io/ncsizemore/jheem-base:${BASE_VERSION}@sha256:34e4116f864bb4df05c9a2d9f4f88781a451dbea036cbf2e340d706cbac19af8
FROM ${BASE_IMAGE} AS base

# jheem2 1.11.1 inherited from base (no override needed)

# --- Build workspace ---
FROM base AS workspace-builder

ARG JHEEM_ANALYSES_COMMIT
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

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-containers"
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

# --- Self-describing identity & provenance ---
# jheem2 inherited from base (not pinned per-model); no workspace skew (built and
# run with the same jheem2). Base simset is the no-intervention scenario (_noint).
# Data is OneDrive-sourced at build time, not yet release-pinned (see jheem-portal
# REPRODUCIBILITY-AND-CITATION-PLAN §5d).
ARG BASE_VERSION
ARG JHEEM_ANALYSES_COMMIT
ENV MODEL_ID=ryan-white-state-croi \
    SIMULATION_SCRIPT=simple_ryan_white.R \
    INTERVENTION_TYPE=permanent_cessation \
    INTERVENTION_START_TIME=2026.5 \
    LOSS_LAG_YEARS=0.25 \
    SIMULATION_START_YEAR=2026 \
    SIMULATION_END_YEAR=2036 \
    REPORTING_START_YEAR=2026 \
    REPORTING_END_YEAR=2031 \
    DEFAULT_OUTCOMES=incidence \
    PARAM_ENV_MAP="adap_loss=ADAP_LOSS oahs_loss=OAHS_LOSS other_loss=OTHER_LOSS" \
    SIMSET_RELEASE=ryan-white-state-v2.0.0 \
    SIMSET_BASE_SUFFIX=_noint \
    JHEEM_ANALYSES_REF=${JHEEM_ANALYSES_COMMIT} \
    JHEEM_BASE_VERSION=${BASE_VERSION}

EXPOSE 8080
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["version"]
