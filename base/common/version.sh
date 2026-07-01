#!/bin/bash
# =============================================================================
# version.sh
# =============================================================================
# Prints this image's provenance, so a reviewer can verify exactly what is
# inside (and, once repo versioning lands, cite it). Fields default to the
# image's baked ENV; tag/DOI are placeholders pending the repo-versioning work.
# =============================================================================
set -euo pipefail

# RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE silences renv's "project out-of-sync"
# startup notice, which would otherwise pollute the captured version string.
jheem2_ver="$(RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE R --slave -e "cat(tryCatch(as.character(packageVersion('jheem2')), error=function(e) 'unknown'))" 2>/dev/null || echo unknown)"
ws_ver="${JHEEM2_WORKSPACE_VERSION:-}"

cat <<EOF
JHEEM model container — provenance
  Model ID:           ${MODEL_ID:-<unset>}
  Simulation script:  ${SIMULATION_SCRIPT:-<unset>}
  jheem2 (runtime):   ${jheem2_ver}
  jheem2 ref:         ${JHEEM2_REF:-<see renv.lock>}
  jheem2 (workspace): ${ws_ver:-<same as runtime>}
  Base image:         ${JHEEM_BASE_VERSION:-<unset>}
  jheem_analyses ref: ${JHEEM_ANALYSES_REF:-<n/a (prebuilt workspace)>}
  Simset release:     ${SIMSET_RELEASE:-<unset>}
  Git tag:            ${JHEEM_GIT_TAG:-TBD (pending repo versioning)}
  Zenodo DOI:         ${JHEEM_ZENODO_DOI:-TBD (pending Zenodo archival)}
EOF

if [[ -n "$ws_ver" && "$ws_ver" != "$jheem2_ver" ]]; then
  cat <<EOF

  Note: the workspace was serialized with jheem2 $ws_ver but runs against
  jheem2 $jheem2_ver. This skew is intentional (R6 class compatibility);
  results match the published analysis. See the model Dockerfile.
EOF
fi
