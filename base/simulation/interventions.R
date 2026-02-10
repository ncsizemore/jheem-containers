# simulation/interventions.R
# Ryan White intervention creation logic
# Based on model_effects.R from jheem2_interactive

# ============================================================================
# MODEL CONFIGURATION
# ============================================================================

MODEL_CONFIG <- list(
  # Whether this model uses WHOLE.POPULATION for all interventions
  use_whole_population = TRUE,
  # Whether this model supports targeting demographic subgroups
  supports_subgroup_targeting = FALSE
)

#' Model effect configurations for Ryan White interventions
MODEL_EFFECTS <- list(
  # Generic suppression_loss effect that works for any group
  suppression_loss = list(
    quantity_name = function(group_id, suffix = NULL) {
      # Base effect name based on group_id
      base_name <- if (group_id == "adap") {
        "adap.suppression"
      } else if (group_id == "oahs") {
        "oahs.suppression"
      } else if (group_id == "other") {
        "rw.support.suppression"
      } else {
        stop(paste("Unknown group ID for suppression_loss:", group_id))
      }

      # Add suffix if provided
      if (!is.null(suffix)) {
        paste0(base_name, ".", suffix, ".effect")
      } else {
        paste0(base_name, ".effect")
      }
    },
    scale = "proportion",
    value_field = "value",
    create = function(start_time, end_time, value, group_id, recovery_duration = NULL) {
      # Create both expansion and nonexpansion effects
      expansion_effect <- create_standard_effect(
        quantity_name = MODEL_EFFECTS$suppression_loss$quantity_name,
        scale = MODEL_EFFECTS$suppression_loss$scale,
        start_time = start_time,
        end_time = end_time,
        value = value,
        group_id = group_id,
        recovery_duration = recovery_duration,
        suffix = "expansion"
      )

      nonexpansion_effect <- create_standard_effect(
        quantity_name = MODEL_EFFECTS$suppression_loss$quantity_name,
        scale = MODEL_EFFECTS$suppression_loss$scale,
        start_time = start_time,
        end_time = end_time,
        value = value,
        group_id = group_id,
        recovery_duration = recovery_duration,
        suffix = "nonexpansion"
      )

      # Return a list of both effects
      list(expansion_effect, nonexpansion_effect)
    }
  )
)

# ============================================================================
# EFFECT CREATION FUNCTIONS
# ============================================================================

#' Create a standard intervention effect
#' @param quantity_name Name of the quantity to affect or function to dynamically determine quantity
#' @param scale Type of scale (proportion or rate)
#' @param start_time Start year
#' @param end_time End year or NULL/NA/"never" for permanent effect
#' @param value Effect value
#' @param transform Function to transform value (optional)
#' @param group_id Group identifier for dynamic quantity determination (optional)
#' @param recovery_duration Recovery duration in months (optional, default 3 months)
#' @param suffix Optional suffix to add to quantity name (e.g., "expansion" or "nonexpansion")
#' @return jheem intervention effect
create_standard_effect <- function(quantity_name, scale, start_time, end_time, value,
                                   transform = NULL, group_id = NULL, recovery_duration = NULL, suffix = NULL) {
  # Handle dynamic quantity names based on group_id
  if (is.function(quantity_name)) {
    quantity_name <- quantity_name(group_id, suffix)
  }

  # Add suffix if provided
  if (!is.null(suffix) && !grepl(paste0("\\\\.", suffix, "\\\\."), quantity_name)) {
    # Only add suffix if it's not already part of the quantity name
    quantity_name <- gsub("\\\\.$", paste0(".", suffix, "."), quantity_name)
    quantity_name <- gsub("\\\\.$", "", quantity_name) # Remove trailing dot if any
  }

  # Apply transformation if provided
  effect_value <- if (!is.null(transform) && is.function(transform)) {
    transform(value)
  } else if (group_id %in% c("adap", "oahs", "other")) {
    # Special case for Ryan White suppression loss
    1 - (value / 100)
  } else {
    value
  }

  # Convert to numeric
  start_time_num <- suppressWarnings(as.numeric(start_time))

  # Check if this is a temporary or permanent effect
  is_temporary <- !is.null(end_time) &&
    !is.na(end_time) &&
    end_time != "" &&
    end_time != "never"

  # Print debug info
  cat("  Creating", ifelse(is_temporary, "TEMPORARY", "PERMANENT"), "effect:\n")
  cat("    Quantity:", quantity_name, "\n")
  cat("    Start time:", start_time_num, "\n")
  cat("    End time:", ifelse(is_temporary, as.numeric(end_time), "N/A"), "\n")
  cat("    Effect value:", effect_value, "\n")

  # Create appropriate effect based on type
  if (is_temporary) {
    # For temporary effects, use the Ryan White pattern with start/end times
    end_time_num <- suppressWarnings(as.numeric(end_time))

    # Calculate recovery period in years (default to 3 months if not specified)
    recovery_years <- if (!is.null(recovery_duration)) {
      recovery_months <- as.numeric(recovery_duration)
      cat("    Using recovery duration of", recovery_months, "months\n")
      recovery_months / 12 # Convert months to years
    } else {
      cat("    Using default recovery duration of 3 months\n")
      0.25 # Default 3 months (1/4 year)
    }

    cat("    Creating temporary effect ending at", end_time_num, "with recovery duration of", recovery_years, "years\n")

    # Create effect with array of values and times
    create.intervention.effect(
      quantity.name = quantity_name,
      start.time = start_time_num,
      end.time = end_time_num + recovery_years, # Add recovery duration
      effect.values = c(effect_value, effect_value), # Same value at both time points
      apply.effects.as = "value",
      scale = scale,
      times = c(start_time_num + 0.3, end_time_num), # Implementation time and return start time
      allow.values.less.than.otherwise = TRUE,
      allow.values.greater.than.otherwise = FALSE
    )
  } else {
    # For permanent effects, use the simpler pattern
    cat("    Creating permanent effect (never returns)\n")

    create.intervention.effect(
      quantity.name = quantity_name,
      start.time = start_time_num,
      effect.values = effect_value,
      apply.effects.as = "value",
      scale = scale,
      times = start_time_num + 0.3, # Ryan White uses +0.3 from start time
      allow.values.less.than.otherwise = TRUE, # RW specific
      allow.values.greater.than.otherwise = FALSE # RW specific
    )
  }
}

# ============================================================================
# MAIN INTERVENTION CREATION FUNCTION
# ============================================================================

#' Create Ryan White intervention from parameters
#' @param parameters List with adap_suppression_loss, oahs_suppression_loss, other_suppression_loss
#' @param start_time Start year for intervention (default 2025.5)
#' @param end_time End year for intervention (default "never")
#' @param recovery_duration Recovery duration in months (default 12)
#' @return JHEEM intervention object
create_ryan_white_intervention <- function(parameters,
                                           start_time = 2025.5,
                                           end_time = "never",
                                           recovery_duration = 12) {
  cat("🔧 Creating Ryan White intervention with parameters:\n")
  cat("  ADAP suppression loss:", parameters$adap_suppression_loss, "%\n")
  cat("  OAHS suppression loss:", parameters$oahs_suppression_loss, "%\n")
  cat("  Other suppression loss:", parameters$other_suppression_loss, "%\n")
  cat("  Start time:", start_time, "\n")
  cat("  End time:", end_time, "\n")
  cat("  Recovery duration:", recovery_duration, "months\n")

  # Create intervention effects for each group
  all_effects <- list()

  # Group configurations
  groups <- list(
    list(id = "adap", loss = parameters$adap_suppression_loss),
    list(id = "oahs", loss = parameters$oahs_suppression_loss),
    list(id = "other", loss = parameters$other_suppression_loss)
  )

  # Create effects for each group
  for (group in groups) {
    cat("  Creating effects for", group$id, "group (", group$loss, "% loss)...\n")

    # Use the MODEL_EFFECTS configuration to create effects
    group_effects <- MODEL_EFFECTS$suppression_loss$create(
      start_time = start_time,
      end_time = end_time,
      value = group$loss,
      group_id = group$id,
      recovery_duration = recovery_duration
    )

    # Add to overall effects list
    all_effects <- c(all_effects, group_effects)
    cat("    ✅ Created", length(group_effects), "effects for", group$id, "\n")
  }

  # Create the intervention object using JHEEM2 patterns (matching Shiny app exactly)
  intervention_code <- paste0(
    "rw-loss-", start_time, "-",
    if (end_time == "never") "permanent" else end_time
  )

  cat("  Creating intervention object with", length(all_effects), "total effects...\n")

  # Ensure WHOLE.POPULATION exists (should be in workspace)
  if (!exists("WHOLE.POPULATION", envir = .GlobalEnv)) {
    cat("  Creating WHOLE.POPULATION target...\n")
    WHOLE.POPULATION <<- create.target.population(name = "Whole Population")
  }

  # Create intervention using exact Shiny app pattern:
  # WHOLE.POPULATION first, then all effects, then parameters
  intervention <- tryCatch(
    {
      # Construct arguments list exactly like Shiny app
      args <- c(
        list(WHOLE.POPULATION), # Target population first
        all_effects, # Then all effects
        list(
          code = intervention_code,
          overwrite.existing.intervention = TRUE
        )
      )

      # Create intervention using do.call like Shiny app
      do.call(create.intervention, args)
    },
    error = function(e) {
      stop("Failed to create intervention: ", e$message)
    }
  )

  cat("✅ Intervention created with code:", intervention_code, "\n")
  cat("   Total effects:", length(all_effects), "\n")
  
  # Add detailed intervention inspection (exactly like Shiny app)
  cat("\n🔍 Intervention structure (str output):\n")
  str(intervention)
  
  # Also show the actual foregrounds content
  cat("\n🔍 Foregrounds content:\n")
  if (!is.null(intervention$foregrounds) && length(intervention$foregrounds) > 0) {
    for (i in 1:min(3, length(intervention$foregrounds))) {  # Show first 3
      cat("  Foreground", i, ":\n")
      str(intervention$foregrounds[[i]], max.level = 2)
    }
    if (length(intervention$foregrounds) > 3) {
      cat("  ... and", length(intervention$foregrounds) - 3, "more foregrounds\n")
    }
  } else {
    cat("  No foregrounds found\n")
  }
  cat("\n")

  return(intervention)
}

#' Helper function to validate intervention parameters
#' @param parameters List of parameters to validate
#' @return TRUE if valid, stops with error if invalid
validate_intervention_parameters <- function(parameters) {
  required_params <- c("adap_suppression_loss", "oahs_suppression_loss", "other_suppression_loss")

  for (param in required_params) {
    if (is.null(parameters[[param]])) {
      stop("Missing required parameter: ", param)
    }

    value <- parameters[[param]]
    if (!is.numeric(value) || value < 0 || value > 100) {
      stop("Parameter ", param, " must be a number between 0 and 100, got: ", value)
    }
  }

  cat("✅ Intervention parameters validated\n")
  return(TRUE)
}

cat("📦 Interventions module loaded (REAL implementation)\n")
