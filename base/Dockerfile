# =============================================================================
# JHEEM Base Image
# Shared R environment for all JHEEM model containers
# =============================================================================
# Built on rocker/r-ver (Ubuntu 24.04 LTS, pinned R + Posit Package Manager
# binaries) rather than r-base. r-base tracks Debian testing/sid (rolling), so
# its system libs drift out from under us — e.g. libnode jumped to Node 24,
# breaking V8 against the old ABI. rocker is purpose-built for reproducible R:
# a frozen Ubuntu LTS base + RSPM binaries, pinned here by digest.
FROM rocker/r-ver:4.4.2@sha256:df26749182af64d5263bf64149d51a427b476ed28c4e046997143be3f97fdd7c

LABEL org.opencontainers.image.source="https://github.com/ncsizemore/jheem-base"
LABEL org.opencontainers.image.description="Shared base image for JHEEM model containers"

# --- System Dependencies (Ubuntu 24.04 noble) ---
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
    libjpeg-turbo8 \
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
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (used by batch_plot_generator.R --upload-s3; not in noble repos).
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# --- R Configuration ---
RUN R CMD javareconf

WORKDIR /app

# --- R Packages ---
# Rprofile.site points renv at RSPM's noble binaries. No source-compile block or
# library-symlink hacks are needed (those were r-base/Debian workarounds): on
# rocker, RSPM binaries match the system libs natively, so renv::restore()
# installs the locked versions — including V8/sf — straight from binaries.
COPY renv.lock Rprofile.site ./
RUN cp Rprofile.site "$(R RHOME)/etc/Rprofile.site"

RUN R -e "install.packages('renv')" && \
    R -e "renv::init(bare = TRUE)" && \
    echo "source('renv/activate.R')" > .Rprofile

RUN R -e "renv::restore()"

# Verify core packages
RUN R --slave -e "library(jheem2); library(plotly); library(jsonlite); cat('Base packages verified\n')"

# --- Common Scripts ---
COPY common/ ./
COPY simulation/ ./simulation/
COPY plotting/ ./plotting/
COPY tests/ ./tests/

RUN chmod +x container_entrypoint.sh run_simulation.sh version.sh

# Base image doesn't have a default command - model images will set ENTRYPOINT
# This allows model images to add their workspace and then:
#   ENTRYPOINT ["./container_entrypoint.sh"]
#   CMD ["batch"]
