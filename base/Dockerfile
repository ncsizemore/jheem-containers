# =============================================================================
# JHEEM Base Image
# Shared R environment for all JHEEM model containers
# =============================================================================
FROM r-base:4.4.2

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-base"
LABEL org.opencontainers.image.description="Shared base image for JHEEM model containers"

# --- System Dependencies ---
RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
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
    awscli \
    && rm -rf /var/lib/apt/lists/*

# --- Library Symlinks for RSPM Compatibility ---
# These binaries from RSPM expect specific library versions
RUN ARCH_LIB_DIR=$(dpkg-architecture -q DEB_HOST_MULTIARCH) && \
    # libgit2
    LIBGIT2=$(ls /usr/lib/${ARCH_LIB_DIR}/libgit2.so.* 2>/dev/null | grep -E 'libgit2\.so\.[0-9]+\.[0-9]+$' | head -1) && \
    if [ -n "${LIBGIT2}" ]; then ln -sf "${LIBGIT2}" "/usr/lib/${ARCH_LIB_DIR}/libgit2.so.1.5"; fi && \
    # libnode
    LIBNODE=$(ls /usr/lib/${ARCH_LIB_DIR}/libnode.so.* 2>/dev/null | head -1) && \
    if [ -n "${LIBNODE}" ]; then ln -sf "${LIBNODE}" "/usr/lib/${ARCH_LIB_DIR}/libnode.so.108"; fi && \
    # libgdal
    GDAL=$(ls /usr/lib/${ARCH_LIB_DIR}/libgdal.so.* 2>/dev/null | head -1) && \
    if [ -n "${GDAL}" ]; then ln -sf "${GDAL}" "/usr/lib/${ARCH_LIB_DIR}/libgdal.so.32"; fi

# --- R Configuration ---
RUN R CMD javareconf && \
    R -e "install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')"

WORKDIR /app

# --- R Packages ---
COPY renv.lock Rprofile.site ./
RUN cp Rprofile.site /etc/R/

RUN R -e "pak::pkg_install('renv')" && \
    R -e "renv::init(bare = TRUE)" && \
    echo "source('renv/activate.R')" > .Rprofile

# Install packages that need source compilation
RUN R -e "renv::install('units', type = 'source')" && \
    R -e "renv::install('gert', type = 'source')" && \
    R -e "renv::install('V8', type = 'source')" && \
    R -e "renv::install('sf', type = 'source')"

RUN R -e "renv::snapshot(packages = c('units', 'gert', 'V8', 'sf'), update = TRUE)" && \
    R -e "renv::restore()"

# Verify core packages
RUN R --slave -e "library(jheem2); library(plotly); library(jsonlite); cat('Base packages verified\n')"

# --- Common Scripts ---
COPY common/ ./
COPY simulation/ ./simulation/
COPY plotting/ ./plotting/
COPY tests/ ./tests/

RUN chmod +x container_entrypoint.sh

# Base image doesn't have a default command - model images will set ENTRYPOINT
# This allows model images to add their workspace and then:
#   ENTRYPOINT ["./container_entrypoint.sh"]
#   CMD ["batch"]
