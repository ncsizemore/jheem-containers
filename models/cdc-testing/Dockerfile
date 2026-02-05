# Three-stage Dockerfile - self-contained build
# Uses git clone for jheem_analyses dependency

# =============================================================================
# STAGE 1: Base R Environment (Reusable across models)
# =============================================================================
FROM r-base:4.4.2 AS jheem-base

# Install system dependencies and create compatibility symlinks for RSPM binaries
RUN apt-get update && apt-get install -y \
  build-essential \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2-dev \
  libxml2 \
  libgit2-dev \
  libgdal-dev \
  libproj-dev \
  zlib1g-dev \
  libicu-dev \
  pkg-config \
  libfreetype6-dev \
  libpng-dev \
  libjpeg-dev \
  libtiff5-dev \
  libtiff6 \
  libjpeg62-turbo \
  libpng16-16 \
  libfreetype6 \
  libfontconfig1-dev \
  libnode-dev \
  libudunits2-dev \
  cmake \
  libabsl-dev \
  default-jdk \
  python3 \
  python3-pip \
  git \
  && rm -rf /var/lib/apt/lists/* \
  && ARCH_LIB_DIR=$(dpkg-architecture -q DEB_HOST_MULTIARCH) \
  # Symlink for gert (libgit2)
  && ln -s "/usr/lib/${ARCH_LIB_DIR}/libgit2.so.1.9" "/usr/lib/${ARCH_LIB_DIR}/libgit2.so.1.5" \
  # Symlink for V8 (libnode)
  && ln -s "/usr/lib/${ARCH_LIB_DIR}/libnode.so.115" "/usr/lib/${ARCH_LIB_DIR}/libnode.so.108" \
  # Symlink for sf (libgdal) - find actual version and link to .32 that RSPM expects
  && GDAL_ACTUAL=$(ls /usr/lib/${ARCH_LIB_DIR}/libgdal.so.* 2>/dev/null | head -1) \
  && echo "Found GDAL: ${GDAL_ACTUAL}" \
  && if [ -n "${GDAL_ACTUAL}" ]; then ln -sf "${GDAL_ACTUAL}" "/usr/lib/${ARCH_LIB_DIR}/libgdal.so.32"; fi

# After installing Java, reconfigure R to recognize it.
# This must be done BEFORE any R packages that need Java are installed.
RUN R CMD javareconf

# Install pak for faster package management
RUN R -e "install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')"

# Set up working directory
WORKDIR /app

# Copy renv lockfile and configure RSPM for binaries
COPY renv.lock ./
COPY Rprofile.site /etc/R/

# Install renv and check ICU version before restoring packages
RUN R -e "pak::pkg_install('renv')" && \
  R -e "renv::init(bare = TRUE)"

RUN echo "source('renv/activate.R')" > .Rprofile

# Handle problematic packages by installing them from source.
# We are now adding 'sf' to this list.
RUN echo "📦 Pre-installing tricky packages as binaries..." && \
  R -e "renv::install(c('units', 'gert', 'V8'))" && \
  echo "✅ Tricky packages installed."

RUN echo "📦 Pre-installing problematic packages from source..." && \
  R -e "renv::install('sf', type = 'source')" && \
  echo "✅ sf installed from source."

# Snapshot to update lockfile with the versions we just installed
# This prevents renv::restore from trying to downgrade them
RUN echo "📸 Updating lockfile with installed versions..." && \
  R -e "renv::snapshot(packages = c('sf', 'units', 'gert', 'V8'), update = TRUE)" && \
  echo "✅ Lockfile updated"

# Install remaining packages as binaries
RUN  echo "📦 Installing remaining packages as binaries..." && \
  R -e "renv::restore()" && \
  echo "✅ All packages installed successfully"

# Test that all packages are working
RUN R --slave -e "\
  library(jheem2); \
  library(plotly); \
  library(jsonlite); \
  library(locations); \
  library(distributions); \
  cat('✅ Base R environment ready\\n')"

# =============================================================================
# STAGE 2: Workspace Builder (Combined Create and Verify)
# =============================================================================
FROM jheem-base AS workspace-builder

# Build argument for jheem_analyses commit
ARG JHEEM_ANALYSES_COMMIT=fc3fe1d2d5f859b322414da8b11f0182e635993b

WORKDIR /app

# Clone jheem_analyses at specific commit
RUN echo "📦 Cloning jheem_analyses at commit ${JHEEM_ANALYSES_COMMIT}..." && \
  git clone https://github.com/tfojo1/jheem_analyses.git jheem_analyses/ && \
  cd jheem_analyses && \
  git checkout ${JHEEM_ANALYSES_COMMIT} && \
  echo "✅ jheem_analyses cloned successfully"

# Download cached data files from OneDrive using metadata
RUN cd jheem_analyses && \
  mkdir -p cached && \
  echo "📦 Generating download commands from metadata..." && \
  R --slave -e "load('commoncode/data_manager_cache_metadata.Rdata'); for(file in names(cache.metadata)) { cat('wget -O cached/', file, ' \"', cache.metadata[[file]][['onedrive.link']], '\"\n', sep='') }" > download_commands.sh && \
  echo "📥 Downloading cached data files..." && \
  bash download_commands.sh && \
  echo "✅ Downloaded files:" && \
  ls -la cached/

# TODO: Remove this manual copy when google_mobility_data.Rdata 
# is added to the official cache metadata system
COPY cached/google_mobility_data.Rdata jheem_analyses/cached/

RUN mkdir -p workspace_build
COPY create_cdc_testing_workspace.R workspace_build/

RUN echo "🔧 Applying path fixes..." && \
  sed -i 's/USE.JHEEM2.PACKAGE = F/USE.JHEEM2.PACKAGE = T/' jheem_analyses/use_jheem2_package_setting.R && \
  echo "✅ Path fixes applied"

# This single RUN command does EVERYTHING: creates the workspace, and then
# immediately verifies its existence and lists the directory contents.
RUN echo "🔧 Creating and verifying workspace in a single step..." && \
  set -e && \
  cd workspace_build && \
  \
  # Run the R script to create the workspace in the parent directory (/app)
  RENV_PROJECT=/app R -e "tryCatch({ source('/app/renv/activate.R'); source('create_cdc_testing_workspace.R') }, error = function(e) { message('ERROR in R script:'); print(e); quit(status=1) })" --args ../cdc_testing_workspace.RData && \
  \
  echo "  - R script finished. Now verifying file existence..." && \
  # Go back to the parent directory to check for the file
  cd .. && \
  echo "  - Current directory is now $(pwd)" && \
  echo "  - Listing contents of current directory:" && \
  ls -lh && \
  \
  # The final check. If this fails, the file was never written.
  if [ ! -f "cdc_testing_workspace.RData" ]; then \
  echo "❌ VERIFICATION FAILED: cdc_testing_workspace.RData does not exist in $(pwd)" ; \
  exit 1; \
  fi && \
  \
  echo "✅ VERIFICATION SUCCEEDED: cdc_testing_workspace.RData found!"


# We no longer need a separate verification step. If the above command succeeds, we are good.
# The subsequent stage will copy from /app/cdc_testing_workspace.RData

# =============================================================================
# STAGE 3: Final Runtime Container (Minimal)
# =============================================================================
FROM jheem-base AS cdc-testing-model

# Copy only the generated workspace from builder stage
COPY --from=workspace-builder /app/cdc_testing_workspace.RData ./

# Copy runtime scripts and modules from container directory
COPY lambda_handler.R ./
COPY plotting_minimal.R ./
COPY batch_plot_generator.R ./
COPY container_entrypoint.sh ./
COPY simulation/ ./simulation/
COPY plotting/ ./plotting/
COPY tests/ ./tests/

# Make entry point executable
RUN chmod +x container_entrypoint.sh

# Test that workspace loads correctly in final container
RUN R --slave -e "\
  cat('🧪 Testing workspace loading in final container...\\n'); \
  system.time(load('cdc_testing_workspace.RData')); \
  cat('✅ Workspace loaded with', length(ls()), 'objects\\n'); \
  cat('✅ CDCT.SPECIFICATION available:', exists('CDCT.SPECIFICATION'), '\\n'); \
  source('plotting_minimal.R'); \
  if (test_plotting_functionality()) { \
  cat('✅ Plotting functionality working\\n'); \
  } else { \
  cat('❌ Plotting test failed\\n'); \
  quit(status = 1); \
  }"

# Set up for flexible runtime
EXPOSE 8080
ENTRYPOINT ["./container_entrypoint.sh"]
CMD ["lambda"]

# =============================================================================
# Build Instructions:
#
# Build from repository root:
# docker build -t jheem-cdc-testing-model .
#
# Build specific target:
# docker build --target workspace-builder -t workspace-test .
#
# Build with different jheem_analyses commit:
# docker build --build-arg JHEEM_ANALYSES_COMMIT=abc123 -t jheem-cdc-testing-model .
# =============================================================================