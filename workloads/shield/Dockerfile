# SHIELD research/calibration workload spike.
#
# This build requires three named BuildKit contexts:
#   jheem_analyses: a clean checkout at JHEEM_ANALYSES_REF
#   jheem2:         a clean checkout at JHEEM2_REF
#   locations:      a clean checkout at LOCATIONS_REF
#
# build-local.sh verifies those identities before invoking Docker. The source
# trees are copied into the image; no Git or package mutation occurs at runtime.

ARG BASE_IMAGE=ghcr.io/ncsizemore/jheem-base:1.7.0@sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3
FROM ${BASE_IMAGE} AS source-preparer

COPY --from=jheem_analyses / /opt/jheem/jheem_analyses/
COPY --from=jheem2 / /opt/jheem/jheem2/
COPY --from=locations / /opt/jheem/locations/

# Local contexts can contain a .git directory or a worktree pointer. Remove it
# before the clean trees cross into the runtime stage, so Git history and local
# paths do not remain hidden in a lower layer of the distributed image.
RUN rm -rf /opt/jheem/jheem_analyses/.git /opt/jheem/jheem2/.git \
    /opt/jheem/locations/.git

FROM ${BASE_IMAGE} AS runtime

ARG JHEEM_ANALYSES_REF=ae08d999aec0dff644e0f687fdff836e9bcf9d3a
ARG JHEEM2_REF=90b68ad500c12bdfe8f9dc6616e9a846fb4ae3d1
ARG LOCATIONS_REF=2481fc440cf1d981bb1005dd903708a88a528d13
ARG JHEEM2_VERSION=1.12.3.9000
ARG LOCATIONS_VERSION=0.5.0.9000
ARG FILELOCK_VERSION=1.0.3

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-containers" \
      org.opencontainers.image.description="SHIELD research and calibration environment" \
      org.jheem.shield.jheem-analyses-ref="${JHEEM_ANALYSES_REF}" \
      org.jheem.shield.jheem2-ref="${JHEEM2_REF}" \
      org.jheem.shield.locations-ref="${LOCATIONS_REF}"

WORKDIR /app

COPY --from=source-preparer /opt/jheem/ /opt/jheem/

# The shared base owns the broad dependency lock. SHIELD adds one exact CRAN
# package and replaces the base's jheem2 with the exact active source revision.
# Both installs happen at image build time in the base renv project library.
RUN R --slave -e "renv::install('filelock@${FILELOCK_VERSION}', project = '/app')" \
    && R --slave -e "renv::install('/opt/jheem/locations', project = '/app')" \
    && R --slave -e "renv::install('/opt/jheem/jheem2', project = '/app')"

RUN R --slave -e "stopifnot( \
      identical(as.character(packageVersion('filelock')), '${FILELOCK_VERSION}'), \
      identical(as.character(packageVersion('locations')), '${LOCATIONS_VERSION}'), \
      identical(as.character(packageVersion('jheem2')), '${JHEEM2_VERSION}') \
    ); cat('SHIELD dependency overlay verified\n')"

# renv's project library uses symlinks into the build user's global cache.
# Recorded workloads run as an arbitrary host UID, so make only the package
# cache traversable/readable; otherwise renv mistakes the inaccessible package
# for a missing one and attempts a forbidden runtime bootstrap.
RUN chmod o+x /root /root/.cache /root/.cache/R \
    && chmod -R a+rX /root/.cache/R/renv

COPY container-entrypoint.sh preflight.R /opt/shield/
RUN chmod 0755 /opt/shield/container-entrypoint.sh \
    && mkdir -p /work/cache /work/state

ENV JHEEM_ANALYSES_PATH=/opt/jheem/jheem_analyses \
    JHEEM2_PATH=/opt/jheem/jheem2 \
    JHEEM_ANALYSES_REF=${JHEEM_ANALYSES_REF} \
    JHEEM2_REF=${JHEEM2_REF} \
    LOCATIONS_REF=${LOCATIONS_REF} \
    JHEEM_CACHE_DIR=/work/cache \
    JHEEM_ROOT_DIR=/work/state \
    JHEEM_PROVENANCE_SPOOL_DIR=/work/state/provenance-spool \
    SHIELD_INPUT_OFFLINE=true \
    SHIELD_ALLOW_INCOMPLETE=false \
    SHIELD_MAX_ATTEMPTS=1 \
    SHIELD_ALLOW_ROOT=false

ENTRYPOINT ["/opt/shield/container-entrypoint.sh"]
CMD ["preflight"]

FROM runtime AS recorded

ENV SHIELD_CONTAINER_PROFILE=recorded \
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
