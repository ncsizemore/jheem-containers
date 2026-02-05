#!/bin/bash

# container_entrypoint.sh
# Routes container execution to appropriate mode

set -e  # Exit on any error

case "$1" in
  "lambda")
    echo "🚀 Starting Lambda mode (custom simulations)"
    exec R --slave -e "source('lambda_handler.R')"
    ;;
  "batch")
    echo "🔄 Starting Batch mode (pre-run simulations)"
    shift  # Remove 'batch' from args
    exec Rscript batch_plot_generator.R "$@"
    ;;
  "custom")
    echo "🧪 Starting Custom mode (same as lambda)"
    exec R --slave -e "source('lambda_handler.R')"
    ;;
  "test-batch")
    echo "🧪 Testing batch dependencies"
    exec R --slave -e "
      cat('Testing batch plot dependencies...\n')
      source('plotting/batch_dependencies.R')
      cat('✅ Batch dependencies loaded successfully\n')
    "
    ;;
  "test-workspace")
    echo "🧪 Testing workspace"
    exec R --slave -e "
      load('ryan_white_workspace.RData')
      cat('✅ Workspace loaded with', length(ls()), 'objects\n')
      cat('✅ RW.SPECIFICATION available:', exists('RW.SPECIFICATION'), '\n')
      cat('✅ RW.DATA.MANAGER available:', exists('RW.DATA.MANAGER'), '\n')
    "
    ;;
  "debug")
    echo "🐛 Starting debug shell"
    exec /bin/bash
    ;;
  *)
    echo "Usage: $0 {lambda|batch|custom|test-batch|test-workspace} [args...]"
    echo ""
    echo "Modes:"
    echo "  lambda       - Run Lambda handler for custom simulations (default)"
    echo "  batch        - Run batch plot generator for pre-run simulations"
    echo "  custom       - Alias for lambda mode"
    echo "  test-batch   - Test batch plotting dependencies"
    echo "  test-workspace - Test workspace loading"
    echo "  debug        - Start interactive bash shell"
    echo ""
    echo "Examples:"
    echo "  $0 lambda                    # Custom simulation mode"
    echo "  $0 batch --city C.12580 --outcomes incidence --scenarios cessation"
    echo "  $0 test-batch              # Test dependencies"
    exit 1
    ;;
esac
