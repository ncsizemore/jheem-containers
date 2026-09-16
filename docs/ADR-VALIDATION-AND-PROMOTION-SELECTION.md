# Validation Selection and Promotion Eligibility

**Status:** accepted  
**Date:** 2026-09-15  
**Scope:** `.github/workflows/build.yml`

## Decision

The workflow will treat **validation selection** and **promotion eligibility** as separate decisions.

- Validation may deliberately broaden to every model when shared tests, workflow code, or the container
  manifest changes.
- Promotion on a `main` push is allowed only for model images whose own `models/<name>/` build context
  changed in that push.
- An explicit `<model>-vX.Y.Z` tag remains eligible to promote the named model after its full gate passes.
- A base cascade validates all downstream models but never promotes their model-image candidates.
- Pull requests and manual dispatches never promote images.
- Unknown manual image names and unknown release-tag targets fail selection instead of producing a green
  no-op workflow.

The exact candidate digest selected for promotion must still be the digest built and tested in the same
workflow run. This decision narrows *which* candidates may be promoted; it does not weaken the existing
build -> test-by-digest -> promote invariant.

## Context

The original workflow used one model matrix for both testing and promotion. Shared changes under `tests/`
or `.github/` intentionally selected all models so the common gate was exercised. On a push to `main`,
however, that same broad matrix was also promoted.

For example, commit `ceb9441` changed the Ryan White calibration registry and its contract test. The main
workflow correctly validated the shared state, but it also rebuilt and advanced `latest` for all four model
images even though no model build context changed.

That coupling has three undesirable properties:

1. A test, policy, or workflow change can become an image release.
2. `latest` can churn without a corresponding model-source change.
3. Rebuilding a nominally unchanged context can still consume external build inputs, so an unrelated
   change should not implicitly authorize publication of the resulting artifact.

## Selection rules

| Trigger/change | Validation | Model promotion |
| --- | --- | --- |
| `models/<name>/...` | affected model (or broader if shared files also changed) | affected model |
| `base/...` | candidate base plus every model | none; base uses its explicit release path |
| `models.yml` | every model | none unless a model context also changed |
| candidate-behavior or shared tests | every model | none unless a model context also changed |
| workflow implementation | base plus every model | none unless a model context also changed |
| documentation/calibration metadata only | contract job; model validation only when selected by shared tests | none |
| `<model>-vX.Y.Z` tag | named model | named model |
| `base-vX.Y.Z` tag | candidate base plus every model | base only |
| manual dispatch | requested validation target | none |

## Consequences

- A green shared-test change can continue to provide broad compatibility evidence without creating a
  release.
- A model-context change on `main` retains the current automatic `latest` behavior.
- Changes that intentionally require a new model image must include a release-relevant model-context change
  or use the explicit model tag flow.
- The selector has more outputs, so structural tests must protect both the validation and promotion paths.
- Contract-only changes may still be expensive if they touch broadly selected test paths. Optimizing that
  cost is a separate concern and must not weaken release safety.

## Non-goals

- This decision does not change production deployment. The backend still selects deliberate semver tags or
  digests.
- It does not redesign the model manifest or add SHIELD.
- It does not decide whether `latest` should exist long-term; it only ensures that advancing it corresponds
  to a release-relevant source change.
