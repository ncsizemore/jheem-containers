# Test-only source overlay: these calibration names do not exist in the image.
# Replace the opt-in smoke register in an isolated test checkout, then commit it.
register.calibration.info(
    "container.smoke.snapshot0",
    likelihood.instructions = lik.inst.stage0,
    data.manager = SURVEILLANCE.MANAGER,
    end.year = 2030,
    fixed.initial.parameter.values = c(
        "global.transmission.rate.msm" = 1.6, "global.transmission.rate.het" = 1.6),
    parameter.names = c("global.transmission.rate.msm", "global.transmission.rate.het"),
    n.iter = 2, thin = 1, is.preliminary = TRUE, max.run.time.seconds = 30,
    description = "Source snapshot test, not scientific inference"
)
register.calibration.info(
    "container.smoke.snapshot1",
    preceding.calibration.codes = "container.smoke.snapshot0",
    likelihood.instructions = lik.inst.stage0,
    data.manager = SURVEILLANCE.MANAGER,
    end.year = 2030,
    parameter.names = c("global.transmission.rate.msm", "global.transmission.rate.het"),
    n.iter = 2, thin = 1, is.preliminary = TRUE, max.run.time.seconds = 30,
    description = "Source snapshot stage-chaining test, not scientific inference"
)
