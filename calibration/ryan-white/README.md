# Ryan White calibration registry

`registry.yml` is the release-specific allowlist for the planned baseline-only calibration exporter.
It binds each portal model and calibration stage to a simulation release, actual ensemble size,
definition-evidence revision, target set, observed-data manager, and source policy.

The registry is intentionally stricter than serialized simset metadata:

- observation bindings are explicit and never inherited from `corresponding.observed.outcome`;
- the legacy `adap.clients -> non.adap.clients` binding is prohibited;
- active likelihood targets are distinguished from related model-fit checks;
- candidate/reconstructed observations are distinguished from verified display-manager values;
- manager binaries remain controlled while minimal derived payloads may be released.

The registry also pins the compatibility-report commit that justifies target-specific use of the
March 2026 manager. That evidence does not promote it to the historical fitting manager.

The initial EHE set is a public panel allowlist, not a complete representation of the large EHE
likelihood. The Ryan White target sets are exhaustive at the target-family level, including the
non-visual sex-by-risk likelihood component.

`export_calibration.R` produces the public, baseline-only `jheem-calibration/v1` artifact. It must
run with the exact model workspace and release asset because historical serialized simsets depend
on the workspace's registered ontology mappings and function environment. The exporter verifies
the simulation asset, manager binaries, registry, sample count, and calibration code; preserves
separate observed source series; exports 95%/50% posterior bands plus the median; and rejects
non-finite or dimensionally inconsistent results. The raw simulations and controlled manager
binaries are never copied into the artifact.

Example (normally run inside the matching model image):

```sh
Rscript calibration/ryan-white/export_calibration.R \
  --registry calibration/ryan-white/registry.yml \
  --model ryan-white-msa \
  --stage ryan-white \
  --simset /inputs/C.12060_base.Rdata \
  --simulation-asset-name C.12060_base.Rdata \
  --simulation-asset-sha256 "$SIMSET_SHA256" \
  --workspace /app/ryan_white_workspace.RData \
  --runtime-image ghcr.io/ncsizemore/jheem-ryan-white-msa@sha256:... \
  --manager ryan-white-web-display-2025-04-08=/controlled/ryan.white.web.data.manager.rdata \
  --manager ryan-white-full-2026-03-16=/controlled/ryan.white.data.manager.rdata \
  --output /outputs/ryan-white-msa.ryan-white.C.12060.json
```

Run the fast contract tests with:

```sh
pytest -q tests/test_calibration_registry.py tests/test_calibration_artifact.py
Rscript tests/test_calibration_exporter.R
```

The exporter must load this file, select the exact model/stage target set, and fail closed if a
release, manager digest, target, source, or observation mapping differs from the registry.
