# Research Script → Custom Simulation Translation Guide

This directory demonstrates how to translate JHEEM research scripts into user-facing custom simulation implementations. The Ryan White example serves as a reference implementation illustrating the core principles.

## Purpose

Research scripts (like `ryan_white_interventions.R`, `cdc_testing_interventions.R`, etc.) are designed for uncertainty quantification with hundreds or thousands of parameter samples. Custom simulations need deterministic results from user-specified parameters. This guide shows how to bridge that gap while maintaining maximum alignment with research code.

## Files

### `simple_ryan_white.R` - Main Implementation
**Purpose**: Creates Ryan White interventions using direct jheem2 calls, matching research script patterns exactly.

**Key Functions**:
- `create_ryan_white_intervention(parameters)` - Creates intervention from user parameters
- `run_custom_simulation(base_simset, intervention)` - Executes simulation with progress tracking
- `validate_intervention_parameters(parameters)` - Validates user input

### Legacy Files (No Longer Used)
- `interventions.R` - Complex R6 class-based approach (300+ lines)
- `runner.R` - SimulationRunner wrapper class (100+ lines)

## Core Translation Principles

### Principle 1: Maintain Identical Function Calls
Copy the research script's `create.intervention.effect()` and `create.intervention()` calls exactly, changing only the parameter values.

**Research Script Pattern** (applies to any model):
```r
# Create individual effects - COPY THESE EXACTLY
some.effect = create.intervention.effect(
  quantity.name = 'some.model.quantity',
  start.time = START.YEAR,
  effect.values = expression(1-some.parameter.name),  # Expression referencing variable
  # ... keep all other parameters identical
)

# Create complete intervention - COPY STRUCTURE EXACTLY  
intervention = create.intervention(
  some.effect,
  another.effect,
  # ... list all effects from research script
  parameters = RESEARCH.PARAMETER.MATRIX,  # Matrix with uncertainty samples
  WHOLE.POPULATION,  # Or whatever target population
  code = "research-code"
)

# Run intervention - COPY EXACTLY
results = intervention$run(simset, start.year=X, end.year=Y)
```

**Custom Simulation Translation**:
```r
# Create individual effects - SAME FUNCTION CALLS, DIRECT VALUES
some.effect <- create.intervention.effect(
  quantity.name = 'some.model.quantity',  # UNCHANGED
  start.time = START.YEAR,                # UNCHANGED  
  effect.values = 1 - (user_input / 100), # REPLACE: Direct numeric from user
  # ... keep all other parameters identical
)

# Create complete intervention - SAME STRUCTURE
intervention <- create.intervention(
  some.effect,
  another.effect,
  # ... same effect list as research script
  parameters = NULL,          # REPLACE: No uncertainty matrix needed
  WHOLE.POPULATION,          # UNCHANGED
  code = "custom-code"       # REPLACE: Custom identifier
)

# Run intervention - UNCHANGED
results <- intervention$run(base_simset, start.year=X, end.year=Y, verbose=TRUE)
```

### Principle 2: Replace Expressions with Direct Values
**Research scripts** use expressions + parameter matrices for uncertainty quantification:
```r
effect.values = expression(1-some.parameter.name)
parameters = PARAMETER.MATRIX  # N×1000 matrix from sampling
```

**Custom simulations** use direct numeric values from user input:
```r
effect.values = 1 - (user_input / 100)  # Direct calculation
parameters = NULL  # No uncertainty sampling
```

**Rationale**: Users expect deterministic results, not probability distributions.

### Principle 3: Handle Parameter Mapping Thoughtfully
Research scripts often have multiple related effects (e.g., expansion vs nonexpansion states, different demographics). Decide whether users need separate controls or if one parameter can apply to related effects.

**Ryan White Example**: Research script differentiates Medicaid expansion vs non-expansion states
```r
# Research script has separate parameters
lose.adap.expansion.effect = expansion_survey_value  
lose.adap.nonexpansion.effect = nonexpansion_survey_value
```

**Our approach**: Single user parameter applied to both
```r
# Simplified - one user input controls both
adap.expansion.effect.values = 1 - (user_adap_loss / 100)
adap.nonexpansion.effect.values = 1 - (user_adap_loss / 100)  # Same value
```

**Decision factors**: UI complexity, user understanding, existing app patterns

### Principle 4: Add Required Workarounds

#### jheem2 Package Typo Fix
```r
# Fix for jheem2 internal typo where it looks for wrong function name
get.intervention.from.code.from.code <- function(...) {
  get.intervention.from.code(...)
}
```

#### Simulation Set Copying
```r
# Required to avoid modifying original simulation data
base_simset <- copy.simulation.set(base_simset)
```

## User Input Mapping

### API Parameters → Research Script Variables
```r
# User provides:
{
  "adap_suppression_loss": 50,    # 50% loss
  "oahs_suppression_loss": 30,    # 30% loss  
  "other_suppression_loss": 40    # 40% loss
}

# Maps to research script variables:
lose.adap.expansion.effect = 0.50
lose.adap.nonexpansion.effect = 0.50
lose.oahs.expansion.effect = 0.30
lose.oahs.nonexpansion.effect = 0.30
lose.rw.support.expansion.effect = 0.40
lose.rw.support.nonexpansion.effect = 0.40
```

## Progress Tracking

### Current Implementation
- Progress callback tracks simulation execution (1-80 simulations typically)
- Handles jheem2's inconsistent progress reporting
- Provides real-time updates during 4-5 minute execution

### Future Serverless Integration
- Progress callback will write to DynamoDB instead of stdout
- Frontend will poll for progress updates every 10 seconds
- Supports both queue position and simulation progress display

## Testing

### Manual Container Test
```bash
cd /Users/nicholas/Documents/jheem-container-minimal

docker run --rm \
  -v $(pwd)/lambda_handler.R:/app/lambda_handler.R \
  -v $(pwd)/plotting/plot_generator.R:/app/plotting/plot_generator.R \
  -v $(pwd)/simulation/simple_ryan_white.R:/app/simulation/simple_ryan_white.R \
  ncsizemore/jheem-ryan-white-model:latest lambda
```

### Expected Output
- Intervention creation with 6 effects (expansion/nonexpansion × adap/oahs/other)
- Simulation execution with progress tracking (1-80 simulations)
- Plot generation (13 plots total)
- ~4-5 minutes total execution time

## Current Limitations & Known Issues

### Ryan White Implementation Limitations
1. **Single parameter set**: No uncertainty quantification like research script
2. **Same expansion/nonexpansion**: No differentiation between Medicaid expansion states  
3. **Fixed timing**: Uses hardcoded START.YEAR (2025.5) and LOSS.LAG (0.25)
   - **TODO**: Make start year a user parameter for API integration
4. **Fixed intervention type**: Only supports permanent cessation, not temporary interruptions

### General Translation Limitations
1. **Requires manual analysis**: No automated way to identify which research script parameters should become user inputs
2. **Context-dependent decisions**: Parameter mapping choices depend on model domain knowledge
3. **Workaround discovery**: Each model may have unique edge cases requiring fixes

### Future Enhancement Opportunities
1. **User-configurable timing**: Allow users to specify intervention start time and duration
2. **Parameter differentiation**: More granular user controls for complex parameter relationships  
3. **Optional uncertainty**: Allow users to enable uncertainty quantification when desired
4. **Intervention variety**: Support different intervention patterns (temporary, gradual, conditional)

## Migration Guide: Any Research Script → Custom Simulation

Use this process for translating any JHEEM research script (e.g., `cdc_testing_interventions.R`, `prep_interventions.R`, etc.):

### Step 1: Analyze Research Script
1. **Find intervention creation section** - look for `create.intervention.effect` and `create.intervention` calls
2. **Identify parameter matrix** - find the uncertainty quantification matrix (e.g., `RW.effect.values`, `CDC.parameter.matrix`)
3. **Map variable names** - note which expression variables correspond to user-controllable parameters
4. **Understand effect relationships** - identify groups of related effects that could share user parameters

### Step 2: Design User Parameter Mapping
1. **Choose user parameters** - decide which research parameters become user inputs
2. **Group related effects** - determine if multiple effects can share single user parameters  
3. **Set parameter ranges** - establish reasonable min/max values and defaults
4. **Plan UI complexity** - balance granular control vs ease of use

### Step 3: Implement Translation
1. **Copy research structure exactly** - same function names, same parameter lists
2. **Replace expressions with direct calculations** - `expression(1-var)` → `1-(user_input/100)`
3. **Set parameters to NULL** - eliminate uncertainty matrix
4. **Add progress tracking** - include `listener` in `intervention$run()`
5. **Test against research script** - verify identical structure and reasonable results

### Step 4: Handle Edge Cases
1. **Add workarounds** - fix any model-specific issues (typos, missing functions, etc.)
2. **Copy simulation set** - use `copy.simulation.set()` to avoid modifying original data
3. **Document deviations** - note any changes from research script and rationale

### Step 5: Validate Results
1. **Compare outputs** - ensure custom simulation produces reasonable results vs research script
2. **Test parameter ranges** - verify extreme values don't break simulation
3. **Check plot generation** - confirm all expected outputs are produced

This systematic approach maintains research script compatibility while creating maintainable user-facing implementations.