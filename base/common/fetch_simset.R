#!/usr/bin/env Rscript
# =============================================================================
# fetch_simset.R
# =============================================================================
# Fetch the base simset for a location from a jheem-simulations GitHub Release.
#
# Caches assets by (release, name) under cache_dir; symlinks the location's base
# simset into link_dir (/data, where custom_simulation.R reads). Integrity is
# checked against the release's reported asset size (guards silent truncation).
#
# Usage:
#   fetch_simset.R <release> <location> <cache_dir> <link_dir> [repo] [base_suffix]
# =============================================================================
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) {
  stop("usage: fetch_simset.R <release> <location> <cache_dir> <link_dir> [repo] [base_suffix]")
}
release   <- args[1]
location  <- args[2]
cache_dir <- args[3]
link_dir  <- args[4]
repo      <- if (length(args) >= 5 && nzchar(args[5])) args[5] else "ncsizemore/jheem-simulations"
suffix    <- if (length(args) >= 6 && nzchar(args[6])) args[6] else "_base"

dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(link_dir,  recursive = TRUE, showWarnings = FALSE)

api <- sprintf("https://api.github.com/repos/%s/releases/tags/%s", repo, release)
rel <- tryCatch(
  fromJSON(api, simplifyVector = FALSE),
  error = function(e) stop(sprintf("Failed to query release %s @ %s: %s",
                                   repo, release, conditionMessage(e)))
)
assets <- rel$assets
if (is.null(assets) || length(assets) == 0) {
  stop(sprintf("Release %s @ %s has no assets", repo, release))
}

# The custom run needs the location's *base* simset, not the prerun scenarios.
is_match <- function(a) {
  grepl(location, a$name, fixed = TRUE) &&
    grepl(suffix, a$name, fixed = TRUE) &&
    grepl("\\.Rdata$", a$name, ignore.case = TRUE)
}
matches <- Filter(is_match, assets)
if (length(matches) == 0) {
  stop(sprintf("No base simset (matching '%s' + '%s') in %s @ %s",
               location, suffix, repo, release))
}

# Large state simsets (~0.8-1.3 GB) truncate on a single download.file with no
# retry. Resume + retry + verify size against the release-asset metadata.
download_with_retry <- function(url, dest, expected_size, tries = 5L) {
  for (i in seq_len(tries)) {
    if (file.exists(dest) && file.size(dest) == expected_size) return(invisible(TRUE))
    # -C - resumes a truncated partial across attempts; --retry-all-errors covers
    # mid-transfer resets; -f fails on HTTP errors; -L follows redirects.
    status <- system2("curl", c("-fL", "--retry", "5", "--retry-delay", "3",
                                "--retry-all-errors", "-C", "-", "-o", dest, url))
    if (file.exists(dest) && file.size(dest) == expected_size) return(invisible(TRUE))
    cat(sprintf("  attempt %d incomplete (%.0f/%.0f MB, curl=%s); retrying\n", i,
                (if (file.exists(dest)) file.size(dest) else 0) / 1e6, expected_size / 1e6, status))
    Sys.sleep(2 * i)
  }
  stop(sprintf("download failed after %d attempts (need %d bytes): %s", tries, expected_size, url))
}

for (a in matches) {
  dest <- file.path(cache_dir, a$name)
  if (file.exists(dest) && file.size(dest) == a$size) {
    cat(sprintf("  cache hit: %s (%.0f MB)\n", a$name, a$size / 1e6))
  } else {
    cat(sprintf("  downloading: %s (%.0f MB)\n", a$name, a$size / 1e6))
    download_with_retry(a$browser_download_url, dest, a$size)
  }
  link <- file.path(link_dir, a$name)
  if (normalizePath(dest, mustWork = FALSE) != normalizePath(link, mustWork = FALSE)) {
    unlink(link)
    if (!file.symlink(normalizePath(dest), link)) file.copy(dest, link, overwrite = TRUE)
  }
}
cat(sprintf("Ready: %d base simset file(s) for %s in %s\n", length(matches), location, link_dir))
