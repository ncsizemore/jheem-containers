# Configuration Ownership and Cross-Repo Contracts

**Status:** target architecture  
**Date:** 2026-07-01  
**Scope:** `jheem-containers`, `jheem-backend`, and the future container `models.yml`

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

Without this boundary, `models.yml` would become another drift surface alongside Dockerfiles,
`tests/test_config.json`, backend `models.json`, documentation, and workflow defaults.

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
| Golden/perturbation test locations and values | Container `models.yml` | Generated `tests/test_config.json` | Test design belongs with the container gate, but parameter ids should reference backend-owned ids. |
| Release notes / archival DOI / image digest report | Container release metadata | Backend may consume/pin | Provenance artifact, not product config. |

## Expected `models.yml` role

`models.yml` should describe the container release contract, not the full application model.

A future entry should look conceptually like this:

```yaml
models:
  ryan-white-ajph:
    backend_model_id: ryan-white-state-ajph
    image: ghcr.io/ncsizemore/jheem-ryan-white-ajph
    context: models/ryan-white-ajph
    template: from-source

    base:
      image: ghcr.io/ncsizemore/jheem-base
      version: 1.6.5
      digest: sha256:34e4116f864bb4df05c9a2d9f4f88781a451dbea036cbf2e340d706cbac19af8

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

The following should eventually be generated from or validated against `models.yml`:

- model Dockerfile `ARG BASE_VERSION`;
- model Dockerfile base digest;
- model Dockerfile default `CMD`;
- model Dockerfile provenance `ENV`;
- `tests/test_config.json`;
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
5. Validate generated or mirrored test config agrees with `models.yml`.
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

## Migration path

1. Add `models.yml` with only container-owned fields.
2. Add local validation against Dockerfiles and `tests/test_config.json`.
3. Generate `tests/test_config.json` from `models.yml`, or make CI fail if it drifts.
4. Generate or validate `PARAM_ENV_MAP` from backend-owned `customSimulation.parameters`.
5. Add cross-repo validation against backend `models.json`.
6. Move the GitHub Actions matrix to read from `models.yml`.
7. Only then consider Dockerfile templates.

The ordering matters. Do not combine canonical-config work with a large Dockerfile-template refactor unless
the validation layer is already in place.

## Non-goals

- Do not move portal display metadata into `models.yml`.
- Do not move S3/CloudFront output config into `models.yml`.
- Do not make backend `models.json` own base digests or Docker build details.
- Do not require backend production to consume `latest`; production should keep pinning deliberate release
  tags or digests.
- Do not treat golden regression tests as scientific validation. They verify reproduction and release
  safety, not model correctness.

## Current status

As of 2026-07-01:

- backend `models.json` remains the application/runtime/product manifest;
- container `models.yml` does not yet exist;
- Dockerfiles are digest-pinned to `jheem-base`;
- `tests/test_base_pin.py` validates base version/digest drift;
- `tests/test_config.json` is still a hand-maintained interim manifest;
- cross-repo validation against backend `models.json` is not yet implemented.

The next configuration milestone should be introducing `models.yml` with this ownership boundary and adding
validation before using it to refactor Dockerfiles.
