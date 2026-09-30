# SHIELD research/calibration workload spike.
#
# This build requires five named BuildKit contexts:
#   jheem_analyses:       a clean checkout at JHEEM_ANALYSES_REF
#   jheem2:               a clean checkout at JHEEM2_REF
#   locations:            a clean checkout at LOCATIONS_REF
#   bayesian_simulations: a clean checkout at BAYESIAN_SIMULATIONS_REF
#   distributions:        a clean checkout at DISTRIBUTIONS_REF
# The last two match the team servers' pins (jhu-servers config/team-packages.txt).
#
# build-local.sh verifies those identities before invoking Docker. The source
# trees are copied into the image; no Git or package mutation occurs at runtime.

ARG BASE_IMAGE=ghcr.io/ncsizemore/jheem-base:1.7.0@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3
FROM ${BASE_IMAGE} AS source-preparer

COPY --from=jheem_analyses / /opt/jheem/jheem_analyses/
COPY --from=jheem2 / /opt/jheem/jheem2/
COPY --from=locations / /opt/jheem/locations/
COPY --from=bayesian_simulations / /opt/jheem/bayesian.simulations/
COPY --from=distributions / /opt/jheem/distributions/

# Local contexts can contain a .git directory or a worktree pointer. Remove it
# before the clean trees cross into the runtime stage, so Git history and local
# paths do not remain hidden in a lower layer of the distributed image.
RUN rm -rf /opt/jheem/jheem_analyses/.git /opt/jheem/jheem2/.git \
    /opt/jheem/locations/.git /opt/jheem/bayesian.simulations/.git \
    /opt/jheem/distributions/.git

FROM ${BASE_IMAGE} AS runtime

ARG JHEEM2_REF=ccb1f9bfe40844143dbcec65ffd27829aa39d7ef
ARG LOCATIONS_REF=2481fc440cf1d981bb1005dd903708a88a528d13
ARG BAYESIAN_SIMULATIONS_REF=4e0d13e85857396bb0e6e2ac1d244775b2145f75
ARG DISTRIBUTIONS_REF=4d71d9644b4439a59210e804520ac8717ae8f079
ARG JHEEM2_VERSION=1.12.3.9000
ARG LOCATIONS_VERSION=0.5.0.9000
ARG BAYESIAN_SIMULATIONS_VERSION=0.2.2
ARG DISTRIBUTIONS_VERSION=1.0.0
ARG FILELOCK_VERSION=1.0.3

WORKDIR /app

# The team packages change rarely and SHIELD code often, so the packages are
# installed before the SHIELD code is copied (and before its revision is
# declared): a SHIELD-only change then reuses the installed layers.
COPY --from=source-preparer /opt/jheem/jheem2/ /opt/jheem/jheem2/
COPY --from=source-preparer /opt/jheem/locations/ /opt/jheem/locations/
COPY --from=source-preparer /opt/jheem/bayesian.simulations/ /opt/jheem/bayesian.simulations/
COPY --from=source-preparer /opt/jheem/distributions/ /opt/jheem/distributions/

# The shared base owns the broad dependency lock. SHIELD adds one exact CRAN
# package and replaces the base's team packages with the exact revisions the
# team servers run. They are installed without kept source references: kept
# references make every saved simulation carry the package's lazy-load state
# (about 5.6 GB per stored simulation in SHIELD calibration chunks, against
# about 20 MB natively), and R's default install omits them.
RUN R --slave -e "renv::install('filelock@${FILELOCK_VERSION}', project = '/app')"

# renv prints status messages on startup; keep only the last output line.
RUN cd /app \
    && export RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE \
    && LIB="$(Rscript -e 'writeLines(.libPaths()[1])' | tail -n 1)" \
    && LIBS="$(Rscript -e 'writeLines(paste(.libPaths(), collapse = ":"))' | tail -n 1)" \
    && test -d "$LIB" \
    && for pkg in distributions bayesian.simulations locations jheem2; do \
         R_LIBS="$LIBS" R CMD INSTALL --without-keep.source --no-test-load \
           -l "$LIB" "/opt/jheem/$pkg" || exit 1; \
       done

RUN cd /app && R --slave -e "stopifnot( \
      identical(as.character(packageVersion('filelock')), '${FILELOCK_VERSION}'), \
      identical(as.character(packageVersion('locations')), '${LOCATIONS_VERSION}'), \
      identical(as.character(packageVersion('jheem2')), '${JHEEM2_VERSION}'), \
      identical(as.character(packageVersion('bayesian.simulations')), '${BAYESIAN_SIMULATIONS_VERSION}'), \
      identical(as.character(packageVersion('distributions')), '${DISTRIBUTIONS_VERSION}') \
    ); \
    for (p in c('distributions', 'bayesian.simulations', 'locations', 'jheem2')) { \
      ns <- asNamespace(p); \
      kept <- Filter(function(f) is.function(f) && !is.null(attr(f, 'srcref')), mget(ls(ns, all.names = TRUE), envir = ns)); \
      if (length(kept)) stop(p, ' has functions with kept source references'); \
    }; \
    cat('SHIELD dependency overlay verified\n')"

# renv's project library uses symlinks into the build user's global cache.
# Recorded workloads run as an arbitrary host UID, so make only the package
# cache traversable/readable; otherwise renv mistakes the inaccessible package
# for a missing one and attempts a forbidden runtime bootstrap.
RUN chmod o+x /root /root/.cache /root/.cache/R \
    && chmod -R a+rX /root/.cache/R/renv

ARG JHEEM_ANALYSES_REF=373faf2775f584093ac16c17ce18432959c609d9
COPY --from=source-preparer /opt/jheem/jheem_analyses/ /opt/jheem/jheem_analyses/

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-containers" \
      org.opencontainers.image.description="SHIELD research and calibration environment" \
      org.jheem.shield.jheem-analyses-ref="${JHEEM_ANALYSES_REF}" \
      org.jheem.shield.jheem2-ref="${JHEEM2_REF}" \
      org.jheem.shield.locations-ref="${LOCATIONS_REF}" \
      org.jheem.shield.bayesian-simulations-ref="${BAYESIAN_SIMULATIONS_REF}" \
      org.jheem.shield.distributions-ref="${DISTRIBUTIONS_REF}"

COPY container-entrypoint.sh preflight.R /opt/shield/
RUN chmod 0755 /opt/shield/container-entrypoint.sh \
    && mkdir -p /work/cache /work/state

ENV JHEEM_ANALYSES_PATH=/opt/jheem/jheem_analyses \
    JHEEM2_PATH=/opt/jheem/jheem2 \
    JHEEM_ANALYSES_REF=${JHEEM_ANALYSES_REF} \
    JHEEM2_REF=${JHEEM2_REF} \
    LOCATIONS_REF=${LOCATIONS_REF} \
    BAYESIAN_SIMULATIONS_REF=${BAYESIAN_SIMULATIONS_REF} \
    DISTRIBUTIONS_REF=${DISTRIBUTIONS_REF} \
    JHEEM_CACHE_DIR=/work/cache \
    JHEEM_ROOT_DIR=/work/state \
    SHIELD_ALLOW_ROOT=false \
    OPENBLAS_NUM_THREADS=1

ENTRYPOINT ["/opt/shield/container-entrypoint.sh"]
CMD ["preflight"]

FROM runtime AS recorded

# Recorded mode in jheem_analyses (applications/SHIELD/RECORDED-RUN-PILOT.md):
# declared source revisions and manager releases, verified offline inputs, and
# non-destructive fresh/resume state rules.
ENV SHIELD_RECORDED_RUN=true \
    SHIELD_CONTAINER_PROFILE=recorded \
    JHEEM2_MODE=package \
    SHIELD_REQUIRE_IMMUTABLE_INPUTS=true \
    SHIELD_RUN_MODE=resume

FROM runtime AS development

# A developer can override these paths with bind mounts and -e declarations.
# Git metadata in a bind-mounted checkout lets provenance record dirty state.
ENV SHIELD_CONTAINER_PROFILE=development \
    JHEEM2_MODE=source \
    SHIELD_REQUIRE_IMMUTABLE_INPUTS=false \
    SHIELD_RUN_MODE=resume
