#!/usr/bin/env bash
# Build the captured jheem2 snapshot (mounted read-only at /opt/run-engine/jheem2)
# into /opt/run-engine/build, inside the runtime image. Run by engine_build.py.
set -euo pipefail

# R CMD INSTALL compiles in the source tree, so build from a private copy.
work="$(mktemp -d)"
cp -R /opt/run-engine/jheem2 "$work/jheem2"
chmod -R u+w "$work/jheem2"

# The image's renv project library supplies jheem2's dependencies, as in the
# image build. Kept source references would make every saved simulation carry
# the package's lazy-load state (see README), so install without them.
cd /app
export RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE
LIBS="$(Rscript -e 'writeLines(paste(.libPaths(), collapse = ":"))' | tail -n 1)"
R_LIBS="$LIBS" R CMD INSTALL --without-keep.source --no-test-load \
  -l /opt/run-engine/build "$work/jheem2"

Rscript -e '
  library.path <- "/opt/run-engine/build"
  .libPaths(c(library.path, .libPaths()))
  stopifnot(identical(normalizePath(find.package("jheem2")),
                      normalizePath(file.path(library.path, "jheem2"))))
  ns <- loadNamespace("jheem2")
  kept <- Filter(function(f) is.function(f) && !is.null(attr(f, "srcref")),
                 mget(ls(ns, all.names = TRUE), envir = ns))
  if (length(kept)) stop("jheem2 build kept source references")
  cat("Built jheem2", as.character(packageVersion("jheem2", lib.loc = library.path)),
      "with", R.version.string, "\n")'
