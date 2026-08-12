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

Run the fast contract tests with:

```sh
pytest -q tests/test_calibration_registry.py
```

The exporter must load this file, select the exact model/stage target set, and fail closed if a
release, manager digest, target, source, or observation mapping differs from the registry.
