# Independent Review: JHEEM Container Monorepo and Containerization Framework

**Review date:** 2026-06-23  
**Reviewer perspective:** Senior software engineering and research-computing review  
**Repository reviewed:** `jheem-containers` at commit `c68b880`  
**Companion plan:** `jheem-portal/docs/CONTAINER-MONOREPO-MIGRATION-PLAN.md`

## Executive summary

The decision to consolidate the JHEEM model containers into a monorepo is sound. The migration also made
several strong choices:

- relocation was separated from the config-driven refactor;
- Git history was preserved;
- existing GHCR image names were retained;
- production remains pinned to explicit image versions;
- the base was migrated from Debian testing to digest-pinned Rocker/Ubuntu;
- model source commits and production golden outputs were preserved.

These choices create a good foundation for a maintainable and scientifically reproducible container
system.

The present Phase A implementation should not yet be treated as a complete base-to-model CI pipeline,
however. Its most important gap is that a `base/` change schedules all model builds, but those model jobs
do not consume the base image built from the same commit. They run concurrently and continue to pull
previously published semver base tags. The workflow therefore restores build fan-out, but not the actual
base-to-model dependency cascade described in the migration plan.

The second major gap is verification. CI currently builds and publishes images without running the
preserved golden regressions, workspace checks, or mode-level smoke tests. Several concrete runtime
interface defects already demonstrate the value of those checks: the CDC image's default command invokes
a Ryan White-specific handler and fails, and the `test-batch` mode references a file that is no longer
present.

The recommended course is to stabilize the CI and verification model before beginning Phase B. Phase B
will centralize more behavior and make errors more broadly consequential; it should build on a trustworthy
build-by-digest, test, and promotion pipeline.

## Scope and approach

This was an independent review rather than a confirmation of conclusions from the migration session. It
covered:

- the migration plan and intended target architecture;
- repository structure and preserved history;
- all five Dockerfiles;
- common runtime scripts and model workspace builders;
- the build workflow and recent GitHub Actions executions;
- production golden artifacts and their current comparator;
- the backend `models.json` and custom-simulation workflow contracts;
- image metadata and lightweight runtime smoke tests;
- dependency, provenance, security, and scientific-reproducibility considerations.

No repository files were changed during the investigation. Shell, R, Python, and JSON source syntax checks
all passed.

## Overall assessment

### Strong architectural choices

#### 1. Relocate first, refactor second

Separating Phase A from the config-driven Phase B was the right risk-management decision. It preserves a
known-good baseline and makes regressions attributable to either relocation or refactoring rather than an
indistinguishable combination of both.

#### 2. Preserve production image names

Keeping the existing GHCR package names avoids coupling the monorepo migration to a production
configuration change. This substantially reduces operational risk and leaves the eventual organization
namespace cutover as a focused, explicit event.

#### 3. Preserve source history

The imported histories are present and `git log --follow` works across the relocated paths. This is
valuable for understanding research-code workarounds and compatibility decisions whose rationale is not
obvious from current code alone.

#### 4. Pin important model inputs

The from-source models now pin `jheem_analyses` commits. In particular, reconstructing and pinning the CROI
commit closes a real reproducibility hole that previously depended on `HEAD`.

#### 5. Preserve production goldens

The four production artifacts are unusually valuable assets. They guard against silent numerical drift,
which ordinary container build success cannot detect. The fact that all four have been independently
reproduced bit-for-bit gives the project a strong regression baseline.

#### 6. Adopt a stable R base

Moving from the drifting Debian testing package environment to digest-pinned Rocker on Ubuntu 24.04 LTS
was a meaningful improvement. It directly addresses a real cache-cold rebuild failure and simplifies the
R package installation model.

#### 7. Self-describing model images

The baked model identity, simulation script, simset release, base version, and source references are useful
both operationally and for future archival/citation work. The `run` and `version` modes are good ideas and
provide a credible path toward reviewer-runnable scientific artifacts.

## Priority findings

### P0: The base-to-model cascade does not use the newly built base

The workflow selects every image when a path under `base/` changes:

```yaml
if echo "$files" | grep -q '^base/'; then
  pick="ALL"
```

All selected images are then built as independent jobs in one matrix. The model Dockerfiles still use
published base versions, for example:

```dockerfile
ARG BASE_VERSION=1.6.1
FROM ghcr.io/ncsizemore/jheem-base:${BASE_VERSION} AS base
```

Consequently:

1. the base and model jobs can run concurrently;
2. model jobs pull an existing registry tag;
3. they do not consume the base image produced by the current commit;
4. a successful workflow does not prove that the changed base is compatible with its dependents.

The successful five-image manual workflow on 2026-06-23 confirms this execution model: the base and four
model builds began concurrently.

#### Recommendation

Treat the base as an explicit build dependency:

1. build the candidate base;
2. export it to the registry under a commit-scoped temporary tag or capture its digest;
3. pass that immutable reference into dependent model builds;
4. test the dependent images;
5. promote only tested digests to `latest` or semver tags.

It is useful to distinguish two concepts:

- **compatibility fan-out:** test all models against a candidate shared-base change;
- **release fan-out:** deliberately release only models that should adopt that base.

This distinction matters because MSA intentionally has different `jheem2` compatibility constraints.

### P0: Published images are not gated by model-output regression tests

The workflow currently performs build and push only. It does not execute:

- the production golden comparisons;
- `test-workspace`;
- lightweight `version` or entrypoint checks;
- model contract checks;
- security or dependency scans.

Only the MSA directory currently contains an executable golden runner and comparator. The AJPH, CROI, and
CDC directories preserve their artifacts and validation notes but do not provide executable test
plumbing.

This means a green release build proves that Docker completed successfully, not that the model remains
numerically equivalent.

#### Recommendation

Create a shared, parameterized test suite covering all four models. At minimum:

- verify each image's expected workspace and specification object;
- run the model's fixed custom scenario;
- compare the expected output slice against the committed golden;
- validate image identity and provenance fields;
- smoke-test every advertised entrypoint mode.

For releases, use a build-once workflow:

```text
build candidate digest -> smoke tests -> golden tests -> attest/scan -> promote digest
```

Do not rebuild between testing and promotion.

### P0: Batch extraction can publish partial result sets

`batch_plot_generator.R` logs a missing scenario file and continues without incrementing its error count.
The backend custom-simulation workflow separately records the batch exit code but only fails when zero JSON
files were generated.

Together, these behaviors permit a run to publish a nonempty but incomplete result set.

This is a particularly important failure mode for research output: partial data may look plausible and be
served successfully while silently omitting requested combinations.

#### Recommendation

- Count missing and unloadable scenario files as errors.
- Fail batch extraction when any requested scenario cannot be processed.
- Generate an expected-output manifest from requested outcomes, statistics, and facets.
- Validate the produced files against that manifest before upload.
- Record explicit exclusions for combinations that are scientifically or structurally unavailable.

### P1: Automatic path selection can produce misleading green workflows

The automatic `main` run for commit `c68b880` selected no images and skipped the build job. It was reported
as successful even though it did not validate any image.

There are two broader path-selection concerns:

1. root files and workflow changes do not trigger builds;
2. pull requests do not provide `github.event.before`, so the fallback to `HEAD~1..HEAD` may inspect only
   the last commit rather than the complete PR change set.

Phase B will add additional shared paths such as `models.yml` and `build/`; those must trigger the correct
fan-out.

#### Recommendation

- Compare pull requests against the merge base with the target branch.
- Treat changes to the workflow, root model manifest, shared templates, test framework, and dependency
  tooling as affecting all relevant images.
- Add a required selection/validation job that fails or reports an intentional no-op distinctly, rather
  than allowing skipped builds to look equivalent to validated builds.
- Generate the build matrix from the canonical model manifest rather than maintaining a second hardcoded
  model list in shell.

### P1: Cache-cold builds still consume mutable external inputs

Pinning the Rocker image digest solves only one layer of reproducibility. Current builds still consume:

- mutable Ubuntu package repositories;
- the `noble/latest` Posit Package Manager endpoint;
- an unversioned AWS CLI archive without checksum verification;
- an initially installed `renv` version that is not explicitly pinned in the install command;
- OneDrive-hosted model data without committed checksums;
- an MSA workspace source referenced by a mutable registry tag;
- simset release assets verified by file size rather than cryptographic digest.

The OneDrive data is the most consequential issue from a scientific-reproducibility perspective. A source
commit and package lockfile cannot reproduce an image if the data behind a URL has changed.

#### Recommendation

Introduce an immutable input manifest for each model containing:

- source URL or archival identifier;
- expected filename;
- SHA-256 digest;
- byte size;
- acquisition date;
- license and redistribution status;
- model/source version that expects the input.

Prefer versioned GitHub release assets, archival storage, or another immutable data repository over
mutable OneDrive links. Pin the MSA workspace source by image digest. Verify all downloaded executables and
data cryptographically.

For stronger environment reproducibility, consider dated package snapshots or an internally retained
binary/package archive rather than `latest` package endpoints.

### P1: The shared base advertises model-specific and nonfunctional modes

The common entrypoint exposes `lambda`, `trim`, and `test-batch` to every model, but their implementations
are not actually generic:

- `lambda_handler.R` hardcodes `ryan_white_workspace.RData` and Ryan White functions.
- CDC and CROI default to `CMD ["lambda"]`.
- Running the published CDC image with no arguments fails because it contains
  `cdc_testing_workspace.RData`, not the Ryan White workspace.
- `test-batch` sources `plotting/batch_dependencies.R`, but the repository contains only
  `batch_dependencies.R.backup`.
- `base/common/trim_simsets.R` is byte-identical to the CROI-specific copy, so all models inherit a CROI
  trimmer.

The CDC image's `test-workspace` command does pass and correctly identifies `CDCT.SPECIFICATION`, which
shows that the workspace itself is healthy; the defect is in the advertised interface.

#### Recommendation

- Remove modes that are not part of the supported generic contract.
- Move model-specific handlers and trimmers into their model directories.
- Make the default command print usage or provenance unless a real long-running service is implemented.
- Add a table of supported modes per model to the canonical manifest.
- Test every supported/default mode in CI.

### P1: Historical tags were not fully preserved

The migration plan called for prefix-renaming imported tags. The five source repositories collectively
contain more tags than the monorepo currently exposes. Common names such as `v1.0.0` collided, leaving
several annotated tag objects dangling and other lightweight refs absent.

The commit history is preserved, but the release/tag history is incomplete and ambiguous.

#### Recommendation

Before archiving the source repositories:

- recreate every historical tag under an unambiguous namespace, for example:
  - `base/v1.6.1`
  - `ryan-white-msa/v1.0.1`
  - `ryan-white-croi/v2.2.0`
  - `cdc-testing/v2.1.2`
- document that these are legacy source-repository tags;
- reserve the new `<image>-vX.Y.Z` form for monorepo release automation.

### P1: The proposed `models.yml` risks becoming another source of truth

Today, model configuration is spread across:

- Dockerfile `ARG` and `ENV` values;
- the backend's `models.json`;
- workflow defaults;
- model documentation.

Phase B proposes adding a root `models.yml`. Unless ownership is made explicit, this creates another drift
surface rather than eliminating one.

Examples of current drift already exist:

- backend repository fields still point at the old per-model repositories;
- model READMEs describe old image names and base versions;
- root documentation says the CI matrix is in progress although it has landed;
- Dockerfiles contain OCI source labels for old repositories, with workflow-generated labels currently
  masking them on CI builds.

#### Recommendation

Define one canonical schema and generate or validate all downstream representations.

A practical division could be:

- `jheem-containers/models.yml`: build inputs, supported modes, workspace/specification contract,
  provenance, and image release identity;
- backend `models.json`: user-facing model, data, and orchestration configuration;
- an automated cross-repository check ensures overlapping fields agree.

Alternatively, make one manifest canonical for both repositories and generate the other. The important
property is machine-enforced consistency, not the specific file location.

## Additional engineering findings

### Image size and privilege

The model images are approximately 5–6 GB and run as root. The runtime contains compilers, development
headers, Git, Java, Python, AWS CLI, and a broad 277-package R environment.

This increases:

- pull and startup cost;
- vulnerability surface;
- scan noise;
- operational consequences of arbitrary code execution;
- difficulty understanding the actual runtime dependency set.

#### Recommendation

- Separate builder and runtime stages for the base.
- Install only runtime libraries in final images.
- Split plotting/data-extraction dependencies from simulation dependencies if operationally practical.
- Run as a dedicated non-root user with explicit writable directories.
- Add `.dockerignore` files.
- Produce SBOMs and OCI provenance attestations.
- Add image vulnerability scanning with a documented exception policy.

### Actions and downloaded tooling are not immutably pinned

GitHub Actions use major-version tags such as `actions/checkout@v4` and
`docker/build-push-action@v5`. These are common but mutable references. The AWS CLI installer is also
downloaded and executed without version or checksum pinning.

For a scientific release pipeline, pin Actions to commit SHAs and use dependency update automation to
propose controlled upgrades.

### Golden comparison coverage is narrow

The current comparator checks one `incidence / mean.and.interval / sex` slice with an absolute tolerance
of `1e-6`. That is a useful canary, but:

- it does not cover most outcomes, facets, or statistics present in the artifact;
- it treats values as matching when either side is `null`;
- duplicate indexing keys would overwrite previous rows silently;
- it does not verify metadata/provenance;
- the example scenarios use default parameter values, which can hide ignored-parameter defects.

One example is the standalone CDC command documented with
`--param proportion_tested_regardless=50`. The `run` wrapper converts that to
`PROPORTION_TESTED_REGARDLESS`, while the model script reads `PROPORTION_TESTED`. The supplied value is
ignored, but this is invisible because the model's default is also 50. Production is not affected because
the backend maps the user-facing parameter to the correct environment variable.

#### Recommendation

- Use at least one non-default parameter value per model.
- Add perturbation tests proving each parameter changes the intended model input and output.
- Compare all high-value outcomes and more than one facet.
- Treat mismatched `null` values as failures.
- Detect duplicate result keys.
- Record the candidate image digest and test input digests in the test report.

### Input matching is permissive

`fetch_simset.R` selects release assets using substring matching for location and suffix. The custom
simulation loader similarly takes the first filename containing the location. These rules can become
ambiguous as asset sets grow.

Use exact model-specific filename patterns from the canonical manifest and fail if the match is not
unique.

### Repository governance metadata is incomplete

The monorepo currently lacks:

- an explicit repository license;
- `CITATION.cff`;
- contribution guidance;
- security reporting guidance;
- ownership/review rules.

Several GitHub-sourced R packages in the lockfile also retain placeholder license metadata, and bundled
Google mobility data needs an explicit provenance and redistribution record.

These issues matter more for a repository intended to support citable scientific artifacts than they
would for an ordinary private deployment repository.

## Research-computing assessment

The production goldens establish **computational regression equivalence**. They do not by themselves
establish scientific correctness.

Three builds using the same model implementation can agree bit-for-bit while sharing the same conceptual
or implementation defect. The goldens should therefore be paired with domain-aware scientific contracts.

Recommended scientific tests include:

- parameter boundary behavior at 0 and 100;
- monotonic or directional expectations where epidemiologically justified;
- nonnegative and finite counts/rates;
- proportions constrained to valid ranges;
- equivalence of a no-change intervention to baseline where applicable;
- invariants across aggregation levels;
- expected simulation horizon and anchor year;
- representative locations covering Medicaid expansion/non-expansion or other meaningful model branches;
- deterministic repeatability given the same simset and parameters;
- explicit checks that each user-facing parameter affects the intended intervention quantity.

The project should also distinguish:

- **archival images:** immutable manuscript/release artifacts retained by digest;
- **operational images:** maintained images receiving security and platform updates.

An archival image should never be silently rebuilt under the same release identity.

## Recommended implementation sequence

### Stage 1: Make Phase A trustworthy

1. Fix pull-request and shared-path change detection.
2. Build candidate bases before dependent models.
3. Pass the exact candidate base digest into model builds.
4. Add workspace, version, and supported-mode smoke tests.
5. Implement the shared four-model golden suite.
6. Fail on missing scenarios and incomplete output manifests.
7. Separate build, test, and promotion.

### Stage 2: Close reproducibility and provenance gaps

1. Introduce model input manifests with SHA-256 checksums.
2. Move mutable OneDrive inputs to immutable/versioned storage.
3. Pin the MSA workspace source by image digest.
4. Pin downloaded tooling and Actions.
5. Emit SBOM and build provenance attestations.
6. Ensure `version` reports the full source, data, base, and image identities.

### Stage 3: Clean the runtime contract

1. Remove or relocate model-specific shared-base modes.
2. Change unsafe/nonfunctional defaults to help or version output.
3. Define supported modes per model.
4. Add a non-root runtime user.
5. Reduce final runtime images.

### Stage 4: Recover migration metadata

1. Recreate namespaced legacy tags.
2. Update old repository links and model documentation.
3. Add repository license, citation, contribution, security, and ownership metadata.
4. Archive old repositories only after tag recovery and authoritative-repository documentation.

### Stage 5: Proceed with Phase B

1. Define the canonical model schema.
2. Generate the CI matrix and build arguments from it.
3. Implement the two shared build templates.
4. Preserve explicit model escape hatches for scientifically meaningful exceptions.
5. Run every Phase B candidate through the same smoke and golden gates before promotion.

## Suggested definition of done

The monorepo migration should be considered complete when:

- every shared-base change tests all dependent models against the exact candidate base digest;
- pull requests cannot receive a misleading green result from skipped image validation;
- all four production goldens run automatically and pass before release promotion;
- every advertised/default mode is tested and functional;
- incomplete extraction output fails closed;
- external model data and executable downloads have immutable identities and checksums;
- released images can be traced to repository commit, base digest, source commits, data digests, and
  simset release;
- historical source-repository tags are recoverable under namespaced monorepo tags;
- one canonical model manifest drives or validates all duplicated configuration;
- old container repositories can be archived without losing authoritative history or release metadata.

## Final perspective

The project is moving in the right direction. The strongest aspect of the work is that it already treats
silent numerical drift and scientific provenance as first-class concerns rather than ordinary deployment
details.

The main danger is now subtler: the CI and configuration structure can look more integrated than it
actually is. Scheduling every image is not the same as testing a dependency graph, preserving a golden is
not the same as gating releases with it, and pinning source code is not sufficient when model data and
package feeds remain mutable.

Addressing those gaps before Phase B will make the config-driven refactor substantially safer and will
leave the project with a container framework that is not only easier to maintain, but genuinely defensible
as a reproducible research system.
