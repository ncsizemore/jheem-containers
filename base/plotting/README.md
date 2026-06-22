# Plotting Setup Instructions

## Overview
The plot generation system has been adapted from the batch_plot_generator.R to work in the Lambda container environment.

## Setup Steps

### 1. Copy Required Files from jheem2_interactive
Run the preparation script to copy the necessary plotting dependencies:

```bash
./prepare_plotting_deps.sh
```

This will copy the following files from jheem2_interactive to `plotting/plotting_deps/`:
- `simplot_local_mods.R` - Core plotting functions
- `plotting_local.R` - Plotting utilities
- `plot_data_preparation.R` - Data preparation logic
- `plot_rendering.R` - Rendering logic

### 2. Verify Files
After running the script, verify that all files are copied:

```bash
ls -la plotting/plotting_deps/
```

You should see:
- `baseline_loading.R` (already created - minimal version)
- `load_config.R` (already created - minimal version)
- `simplot_local_mods.R` (copied from jheem2_interactive)
- `plotting_local.R` (copied from jheem2_interactive)
- `plot_data_preparation.R` (copied from jheem2_interactive)
- `plot_rendering.R` (copied from jheem2_interactive)

### 3. Build Container
Once all files are in place, build the Docker container:

```bash
docker build -t jheem-ryan-white-model .
```

## Architecture

### Plot Generation Flow
1. **Lambda Handler** (`lambda_handler.R`)
   - Receives simulation request
   - Loads base simulation (the starting point)
   - Creates intervention based on parameters
   - Runs simulation (applies intervention to base simulation)
   - Calls `generate_simulation_plots()` with both results and baseline

2. **Plot Generator** (`plotting/plot_generator.R`)
   - Defines 10 key plots to generate
   - Calls `generate_single_plot_json()` for each plot
   - Always creates comparison plots (baseline vs intervention)
   - Returns JSON format for API

3. **Batch Dependencies** (`plotting/batch_dependencies.R`)
   - Loads all required plotting functions
   - Sets up mock/minimal functions for container context

### Key Adaptations from Batch Generator
- **No file I/O**: Returns JSON directly instead of writing files
- **Always includes baseline**: Baseline is the starting simulation that intervention is applied to
- **Comparison plots**: All plots show baseline vs intervention results
- **Simplified config**: Minimal configuration for container environment
- **Error handling**: Graceful fallback to error placeholders if individual plots fail

## Plot Configurations
The system generates 10 key plots:
1. `incidence_unfaceted` - Overall incidence
2. `incidence_by_sex` - Incidence by sex
3. `incidence_by_race` - Incidence by race
4. `diagnosed_prevalence_unfaceted` - Overall diagnosed prevalence
5. `diagnosed_prevalence_by_sex` - Diagnosed prevalence by sex
6. `suppression_unfaceted` - Overall viral suppression
7. `suppression_by_sex` - Viral suppression by sex
8. `new_infections_unfaceted` - New infections
9. `mortality_unfaceted` - HIV mortality
10. `prep_coverage_unfaceted` - PrEP coverage

## Testing

### Local Testing
Test the plot generation locally:

```r
# Load workspace and dependencies
source("lambda_handler.R")

# Create test event
test_event <- list(
  city = "C.12580",
  base_simulation_path = "test_base_sim.rdata",
  parameters = list(
    adap_suppression_loss = 50,
    oahs_suppression_loss = 30,
    other_suppression_loss = 40
  )
)

# Run handler
result <- handle_simulation_request(test_event, NULL)
```

### Container Testing
Test in Docker container:

```bash
docker run --rm jheem-ryan-white-model
```

## Troubleshooting

### Missing Dependencies
If plotting fails with missing function errors:
1. Check that all files were copied correctly
2. Verify the jheem2_interactive path in `prepare_plotting_deps.sh`
3. Check `plotting/batch_dependencies.R` for loading errors

### Plot Generation Errors
If specific plots fail:
1. Check the error message in the plot JSON
2. Mock plots will be generated as fallback
3. Review outcome names match simulation outputs

### Memory Issues
If container runs out of memory:
1. Reduce number of plots generated
2. Increase Lambda memory allocation
3. Consider generating plots on-demand instead

## Future Improvements
1. **Dynamic plot selection**: Allow users to specify which plots to generate
2. **Baseline comparison**: Add support for baseline simulations
3. **Caching**: Cache generated plots in S3
4. **On-demand generation**: Generate additional plots after simulation completes
