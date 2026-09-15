# Configuration Ownership and Cross-Repo Contracts

**Status:** implemented architecture

**Date:** 2026-09-15

**Scope:** `jheem-containers/models.yml` and `jheem-backend/.github/config/models.json`

## Summary

The backend already has a model manifest:

- `jheem-backend/.github/config/models.json`

That file should remain the source of truth for **application, runtime, and product model configuration**.

The container monorepo also needs a manifest:

- `jheem-containers/models.yml`

That file should become the source of truth for **container build, test, release, and provenance
configuration**.

These are two different bounded contexts. The goal is not to create two competing sources of truth. The
goal is to make ownership explicit and enforce the overlap by CI.

In short:

```text
backend models.json
  owns public/deployed model behavior

container models.yml
  owns container build/test/provenance behavior

cross-repo contract tests
  enforce every shared field
```

## Why this doc exists

The original monorepo migration plan described `models.yml` as “the single source of truth.” That wording is
too broad now that the backend has a mature `models.json` that already drives backend workflows and portal
configuration.

The sharper target is:

- `models.json` is the source of truth for the application-facing model contract.
- `models.yml` is the source of truth for the container-facing build and release contract.
- Shared facts are validated, not trusted by convention.

Without this boundary, `models.yml` would become another drift surface alongside Dockerfiles, backend
`models.json`, documentation, and workflow defaults. The former hand-maintained
`tests/test_config.json` was deleted; tests now read `models.yml` directly.

## Ownership principles

1. One field, one owner.

   If a field appears in more than one repo, one file still owns it. Other files either mirror it as a
   generated artifact or are validated against it.

2. Backend owns product/runtime semantics.

   If the portal, API, data-generation workflows, or production deployment semantics depend on a field, it
   belongs in backend `models.json`.

3. Containers own build/provenance/test semantics.

   If a field controls how an image is built, tested, pinned, or reproduced, it belongs in container
   `models.yml`.

4. CI validates overlap.

   Shared fields must have automated drift checks. A human review checklist is not sufficient.

5. Production promotion remains explicit.

   The container repo publishes tested images. Backend `models.json` decides which released image tag
   production uses.

## Ownership table

| Field / concern | Owner | Mirrored or validated where | Notes |
| --- | --- | --- | --- |
| Product model id, e.g. `ryan-white-state-ajph` | Backend `models.json` | Container `models.yml` maps to it | Container directory names may be shorter, e.g. `ryan-white-ajph`; the mapping must be explicit. |
| Display name, description, geography labels | Backend `models.json` | Portal generated config | Product/UI concern only. |
| Locations, scenarios, outcomes, facets, statistics | Backend `models.json` | Backend workflows, portal | Container tests may select a subset but should not own product coverage. |
| Output S3/CloudFront paths, summaries, map defaults | Backend `models.json` | Backend/portal | Not container metadata. |
| Production container image tag/version | Backend `models.json` | Validated against GHCR/container releases | Backend decides what production runs. |
| Container image package name | Container `models.yml` | Backend `models.json` validates deployed image names | Containers own what they publish; backend owns which one it deploys. |
| Docker context / template / build strategy | Container `models.yml` | Dockerfiles or generated build matrix | Container-only concern. |
| Base image version and digest | Container `models.yml` | Dockerfiles, `tests/test_base_pin.py` | Backend should not own base internals. |
| `jheem_analyses` commit / source refs | Container `models.yml` | Dockerfiles, `version` output | Build provenance. |
| Workspace strategy/script/spec object | Container `models.yml` | Dockerfiles, smoke tests | Build/test concern. |
| Supported entrypoint modes and default `CMD` | Container `models.yml` | Dockerfiles, smoke tests | Prevents advertising broken modes. |
| Simset/data release used by `run` defaults | Backend owns operational data release; container mirrors for runtime default | Cross-repo validation | This is shared because backend data workflows and container `run` defaults must agree. |
| Custom simulation parameter ids, defaults, labels, units | Backend `models.json` | Container generated/validated `PARAM_ENV_MAP` and perturbation tests | Backend owns user/API contract. |
| Parameter `id -> envVar` mapping | Backend `models.json` | Container `PARAM_ENV_MAP`, tests | The CDC bug came from this drifting. |
| Golden/perturbation test locations and values | Container `models.yml` | Test fixtures and candidate-image behavior tests | Tests read the manifest directly; parameter ids reference backend-owned ids. |
| Release notes / archival DOI / image digest report | Container release metadata | Backend may consume/pin | Provenance artifact, not product config. |

## Expected `models.yml` role

`models.yml` should describe the container release contract, not the full application model.

An entry looks conceptually like this:

```yaml
models:
  ryan-white-ajph:
    backend_model_id: ryan-white-state-ajph
    image: ghcr.io/ncsizemore/jheem-ryan-white-ajph
    context: models/ryan-white-ajph
    template: from-source

    base:
      image: ghcr.io/ncsizemore/jheem-base
      version: 1.7.0
      digest: sha256:a76a92ca41d38c3d7d5f77f79efd2e2fe754f8ee97be6b69aec0ea949c1282c3

    sources:
      jheem_analyses_ref: fc3fe1d2d5f859b322414da8b11f0182e635993b

    runtime:
      model_id: ryan-white-state-ajph
      simulation_script: simple_ryan_white.R
      simset_release: ryan-white-ajph-v1.0.0
      simset_base_suffix: _noint
      default_cmd: version
      supported_modes: [version, run, custom, batch, test-workspace, debug]

    workspace:
      script: create_ryan_white_workspace.R
      file: ryan_white_workspace.RData
      spec_object: RW.SPECIFICATION

    tests:
      golden:
        location: FL
        params:
          adap_loss: 50
          oahs_loss: 30
          other_loss: 40
        artifact: models/ryan-white-ajph/tests/golden/FL_a50-o30-r40.json
      perturbations:
        - param: oahs_loss
          value: 60
```

This intentionally omits display names, portal paths, CloudFront details, full location lists, and map
configuration. Those stay in backend `models.json`.

## Generated or validated artifacts

The following are generated from, read from, or validated against `models.yml`:

- model Dockerfile `ARG BASE_VERSION`;
- model Dockerfile base digest;
- model Dockerfile default `CMD`;
- model Dockerfile provenance `ENV`;
- candidate-image test configuration (read directly by `tests/conftest.py`);
- GitHub Actions build matrix;
- optional shared Dockerfile template inputs.

The following should be validated against backend `models.json`:

- `backend_model_id` exists;
- image package name agrees where backend pins an image;
- simulation script agrees;
- simset/data release agrees;
- custom simulation parameter ids agree;
- parameter `id -> envVar` mappings agree.

## CI contract tests

### Container repo checks

The container repo should have fast structural tests that run on every PR:

1. Parse `models.yml`.
2. Validate every listed model has a Docker context.
3. Validate every model Dockerfile is digest-pinned.
4. Validate every pinned base digest matches the GHCR digest for the claimed base version.
5. Validate test artifacts and parameter selections referenced by `models.yml` exist and are internally
   consistent.
6. Validate Dockerfile provenance fields agree with `models.yml`.

`tests/test_base_pin.py` is the first concrete version of this pattern.

### Cross-repo checks

The container repo should also validate shared fields against backend `models.json`.

Recommended behavior:

- default CI checks against backend `main`;
- coordinated cross-repo changes can override the backend ref explicitly;
- failures should name the owning file and the mirrored field.

The backend should eventually run the reciprocal check: its production-pinned image tags should correspond
to known container images/releases.

### Security note

Container gate tests currently pass `GITHUB_TOKEN` into candidate containers so `fetch_simset.R` can
authenticate GitHub release API requests and avoid rate-limit failures. That token should be scoped as
narrowly as possible at the job level. Build/promotion may need package write privileges; test jobs should
not.

## Completed migration sequence

1. Added `models.yml` with only container-owned fields.
2. Added local validation against Dockerfiles.
3. Deleted `tests/test_config.json` and made the test suite read `models.yml` directly.
4. Validated `PARAM_ENV_MAP` against backend-owned `customSimulation.parameters`.
5. Added cross-repo validation against backend `models.json`.
6. Moved the GitHub Actions build matrix and model path selection to `models.yml`.

Dockerfile templates remain optional. The validation layer is in place, so a future template refactor can be
considered independently rather than being coupled to canonical-configuration work.

## Validation versus promotion

The manifest-driven validation matrix is intentionally allowed to broaden for shared tests, workflow changes,
or base compatibility. Promotion eligibility is narrower: on a `main` push, a model may advance `latest` only
when its own build context changed; explicit model tags may promote only the named model. See
[`ADR-VALIDATION-AND-PROMOTION-SELECTION.md`](ADR-VALIDATION-AND-PROMOTION-SELECTION.md).

## Non-goals

- Do not move portal display metadata into `models.yml`.
- Do not move S3/CloudFront output config into `models.yml`.
- Do not make backend `models.json` own base digests or Docker build details.
- Do not require backend production to consume `latest`; production should keep pinning deliberate release
  tags or digests.
- Do not treat golden regression tests as scientific validation. They verify reproduction and release
  safety, not model correctness.

## Current status

As of 2026-09-15:

- backend `models.json` remains the application/runtime/product manifest;
- container **`models.yml` exists** with the container-owned fields (migration step 1);
- `tests/test_models_yml.py` validates that the Dockerfiles agree with `models.yml` (migration step 2 —
  local drift check; runs on every PR, incl. any `models.yml` change);
- **step 3 done in its strongest form:** `tests/test_config.json` was **deleted**, not generated — the test
  suite reads `models.yml` directly (`conftest.config()`), so there is no mirrored test config to drift;
- Dockerfiles are digest-pinned to `jheem-base`; `tests/test_base_pin.py` validates the pinned digest
  against the registry;
- **step 6 done:** the GitHub Actions build matrix (and the per-model path filter) is generated from
  `models.yml` in the `select` job — no hardcoded model list remains in CI;
- **steps 4+5 done:** `tests/test_cross_repo.py` validates the shared fields against backend
  `models.json` on every PR — param `id -> envVar` maps (backend-owned; the CDC-bug class), simulation
  scripts, image names, simset releases, plus the reverse check that every backend custom-sim model has a
  container. Fetches the (public) backend manifest from `raw.githubusercontent`; `BACKEND_REF` overrides
  the ref for coordinated cross-repo changes; `BACKEND_MODELS_PATH` points at a local clone for offline
  work. A failed fetch fails the suite — never skips.

The validation layer (steps 1–6) is complete. Validation and promotion selection are now independent, so a
shared contract change can test every model without implicitly releasing every model. Remaining,
deliberately later: optional Dockerfile templates and the backend-side reciprocal check that pinned image
tags correspond to released container images. Known backend-side staleness: `container.repository` still
names the old per-model repositories even though the semver pins have moved to monorepo-built releases.
