#!/bin/bash

# container_entrypoint.sh
# Routes container execution to appropriate mode
# BASE IMAGE VERSION: Auto-detects workspace, supports all models

set -e  # Exit on any error

case "$1" in
  "lambda")
    echo "Starting Lambda mode (custom simulations)"
    exec R --slave -e "source('lambda_handler.R')"
    ;;
  "batch")
    echo "Starting Batch mode (pre-run simulations)"
    shift  # Remove 'batch' from args
    exec Rscript batch_plot_generator.R "$@"
    ;;
  "trim")
    echo "Starting Trim mode (raw simset -> web-ready)"
    if [ ! -f "trim_simsets.R" ]; then
      echo "ERROR: trim_simsets.R not found in container"
      exit 1
    fi
    shift  # Remove 'trim' from args
    exec Rscript trim_simsets.R "$@"
    ;;
  "custom")
    echo "Starting Custom simulation mode"
    shift  # Remove 'custom' from args
    exec Rscript custom_simulation.R "$@"
    ;;
  "test-batch")
    echo "Testing batch dependencies"
    exec R --slave -e "
      cat('Testing batch plot dependencies...\n')
      source('plotting/batch_dependencies.R')
      cat('Batch dependencies loaded successfully\n')
    "
    ;;
  "test-workspace")
    echo "Testing workspace (auto-detect)"
    exec R --slave -e "
      # Auto-detect workspace file
      workspace_files <- list.files(pattern = '_workspace\\\\.RData$', ignore.case = TRUE)
      if (length(workspace_files) == 0) {
        stop('No workspace file found')
      }
      workspace_file <- workspace_files[1]
      load(workspace_file)
      cat('Workspace loaded:', workspace_file, '\n')
      cat('Objects:', length(ls()), '\n')

      # Check for known specification objects
      specs <- c('RW.SPECIFICATION', 'CDCT.SPECIFICATION', 'CROI.SPECIFICATION')
      available <- specs[sapply(specs, exists)]
      if (length(available) > 0) {
        cat('Specification:', paste(available, collapse=', '), '\n')
      }

      # Check for known data managers
      dms <- c('WEB.DATA.MANAGER', 'RW.DATA.MANAGER', 'CDCT.DATA.MANAGER')
      available_dms <- dms[sapply(dms, exists)]
      if (length(available_dms) > 0) {
        cat('Data manager:', paste(available_dms, collapse=', '), '\n')
      }
    "
    ;;
  "debug")
    echo "Starting debug shell"
    exec /bin/bash
    ;;
  *)
    echo "Usage: $0 {lambda|batch|trim|custom|test-batch|test-workspace|debug} [args...]"
    echo ""
    echo "Modes:"
    echo "  lambda       - Run Lambda handler for custom simulations"
    echo "  batch        - Run batch plot generator for pre-run simulations"
    echo "  trim         - Trim raw simsets to web-friendly size (if available)"
    echo "  custom       - Run custom simulation (user params → JSON output)"
    echo "  test-batch   - Test batch plotting dependencies"
    echo "  test-workspace - Test workspace loading (auto-detect)"
    echo "  debug        - Start interactive bash shell"
    echo ""
    echo "Examples:"
    echo "  $0 batch --city C.12580 --outcomes incidence --scenarios cessation"
    echo "  $0 trim --state AL --input-dir /data/raw --output-dir /data/trimmed"
    echo "  $0 test-workspace"
    exit 1
    ;;
esac
