# =============================================================================
# JHEEM Ryan White AJPH Model (11 States, 2025-2030)
# Thin wrapper around jheem-base - only adds workspace creation
# =============================================================================
ARG BASE_VERSION=1.7.0
ARG JHEEM_ANALYSES_COMMIT=fc3fe1d2d5f859b322414da8b11f0182e635993b
ARG BASE_IMAGE=ghcr.io/ncsizemore/jheem-base:${BASE_VERSION}@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3
FROM ${BASE_IMAGE} AS base

# jheem2 inherited from base (no override needed)

# --- Build workspace ---
FROM base AS workspace-builder

ARG JHEEM_ANALYSES_COMMIT
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

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-containers"
LABEL org.opencontainers.image.description="JHEEM Ryan White AJPH model (11 states, 2025-2030)"

COPY --from=workspace-builder /app/ryan_white_workspace.RData ./

# Verify workspace
RUN R --slave -e "load('ryan_white_workspace.RData'); \
    cat('Objects:', length(ls()), '\n'); \
    stopifnot(exists('RW.SPECIFICATION')); \
    stopifnot(exists('RW.DATA.MANAGER')); \
    cat('Workspace verified\n')"

# --- Self-describing identity & provenance ---
# State model: jheem2 inherited from base (not pinned per-model); no workspace
# skew (built and run with the same jheem2). Base simset is the no-intervention
# scenario (_noint). Data is OneDrive-sourced at build time, not yet release-
# pinned (see jheem-portal REPRODUCIBILITY-AND-CITATION-PLAN §5d).
ARG BASE_VERSION
ARG JHEEM_ANALYSES_COMMIT
ENV MODEL_ID=ryan-white-state-ajph \
    SIMULATION_SCRIPT=simple_ryan_white.R \
    INTERVENTION_TYPE=permanent_cessation \
    INTERVENTION_START_TIME=2025.5 \
    LOSS_LAG_YEARS=0.25 \
    SIMULATION_START_YEAR=2025 \
    SIMULATION_END_YEAR=2035 \
    REPORTING_START_YEAR=2025 \
    REPORTING_END_YEAR=2030 \
    DEFAULT_OUTCOMES=incidence \
    PARAM_ENV_MAP="adap_loss=ADAP_LOSS oahs_loss=OAHS_LOSS other_loss=OTHER_LOSS" \
    SIMSET_RELEASE=ryan-white-ajph-v1.0.0 \
    SIMSET_BASE_SUFFIX=_noint \
    JHEEM_ANALYSES_REF=${JHEEM_ANALYSES_COMMIT} \
    JHEEM_BASE_VERSION=${BASE_VERSION}

ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["version"]
