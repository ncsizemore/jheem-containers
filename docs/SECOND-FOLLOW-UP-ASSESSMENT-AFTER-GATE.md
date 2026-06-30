# Second Follow-up Assessment After the Test/Promotion Gate Work

**Date:** 2026-06-29  
**Responding to:** `RESPONSE-TO-FOLLOW-UP-ASSESSMENT.md`  
**Perspective:** independent senior SWE / research-software review of the current `feat/test-promotion-gate` branch

## Bottom line

The branch has made a substantial engineering move forward. The most important prior gap — publishing model
images without testing the exact image digest being promoted — is now materially addressed for model images.

I would now describe the state as:

> The monorepo has a credible model-image promotion gate. It does not yet have a complete trustworthy
> release framework, because base-image compatibility, canonical configuration, runtime-contract cleanup,
> and provenance hardening remain open.

That distinction matters. The team should take credit for the gate: it is not just a plan anymore. But the
gate should not be over-described as solving the entire base/model release problem.

## What I verified

I reviewed the current `feat/test-promotion-gate` branch and checked the recent GitHub Actions state.

The branch is clean and tracks `origin/feat/test-promotion-gate`.

The latest feature-branch CI run I found was:

- `28051286482` — `workflow_dispatch`, 2026-06-23T19:25:34Z, successful, 48m25s.

That run built and tested all five matrix entries:

- `base`
- `ryan-white-msa`
- `ryan-white-ajph`
- `ryan-white-croi`
- `cdc-testing`

I also checked the `base-v1.6.2` tag run:

- `28050771275` — tag push, successful, built/tested/promoted the base image.

The qualification on that tag run is important: the current base test path is effectively a no-op for
model compatibility. It demonstrates digest-based base promotion, but it does not prove that downstream
models work against that candidate base.

## What is now materially improved

### 1. The model-image digest gate is real

The workflow now follows the right release shape:

1. build the candidate image;
2. push it under a temporary gate tag;
3. record the immutable image digest;
4. test that exact digest;
5. promote that same digest with `docker buildx imagetools create`;
6. avoid rebuilding between test and promotion.

This is the right architecture. It closes the earlier “test one artifact, publish another” class of problem
for model images.

The implementation is in `.github/workflows/build.yml`. The important behavior is visible in three places:

- the build job pushes `ghcr.io/<owner>/<image>:gate-<sha>`;
- the digest is written to the `ref-<model>` artifact;
- the promote job re-tags the recorded digest, not a fresh build.

That is a meaningful improvement in release integrity.

### 2. The CDC perturbation failure mode is now tested

The test suite now includes a model-output gate with two relevant classes of tests:

- golden regression tests;
- parameter perturbation tests.

The perturbation test is the key improvement. It would have caught the earlier CDC bug, where
`proportion_tested_regardless` did not map to the actual `PROPORTION_TESTED` environment variable consumed
by the model.

The current test asserts the right contract shape:

- perturb only the intervention parameter;
- baseline remains unchanged;
- intervention output changes.

That is exactly the sort of test this framework needs. It is more valuable than another default golden,
because it exercises the parameter plumbing.

### 3. The comparator is more defensible

The comparator now catches issues that the earlier approach could miss:

- missing candidate rows;
- extra candidate rows;
- duplicate index keys;
- null-vs-value mismatches;
- baseline versus intervention differences.

This does not make the tests scientifically comprehensive, but it does make the regression gate much less
fragile than the initial implementation.

### 4. CI evidence supports the main claim

The successful feature-branch run provides useful evidence that the full branch implementation can build and
test the candidate model images. The earlier failed runs are not a concern by themselves; they appear to be
normal iteration while getting a heavy Docker/R workflow stable on GitHub-hosted runners.

The successful 48-minute run is the one I would cite as the evidence point.

## Important qualifications

### 1. Base-image compatibility is still not gated

This is the main caveat.

The gate works for model-image candidates. It does not yet implement a true candidate-base cascade.

Currently, when the matrix entry is `base`, the test step exits early with:

```text
base has no model tests
```

So the `base-v1.6.2` tag run proves:

- the base image built;
- the base candidate digest was recorded;
- the base digest was promoted.

It does not prove:

- MSA works against the base candidate;
- AJPH works against the base candidate;
- CROI works against the base candidate;
- CDC works against the base candidate;
- a base change is safe to promote relative to downstream model behavior.

The response acknowledges this under “Phase B true digest cascade,” and that is the correct framing. But the
team should be precise in future language:

- “model-image digest gate” is accurate;
- “complete base/model release gate” is not yet accurate.

### 2. PR validation is not the full gate

On `pull_request`, the workflow runs only the non-slow tests. The golden and perturbation tests are marked
slow, so they are skipped in normal PR validation.

That is a reasonable cost-control decision if the workflow is expensive. But then the process needs an
explicit rule:

- either require a manual full gate run before merge for release-impacting changes;
- or run slow tests automatically for changes to `base/`, `models/`, `tests/`, and workflow files;
- or separate fast PR validation from required pre-release validation.

Without that rule, it is possible for a PR to appear green without having run the model-output tests that
make the gate meaningful.

### 3. The test suite is strong but still narrow

The new tests are a major improvement, but they should not be overinterpreted.

Current limitations:

- the perturbation test appears to cover one configured parameter per model, not every parameter;
- golden comparison still centers on the configured scenario/slice, not a broad scientific validation suite;
- the tests verify reproduction and parameter plumbing, not model correctness;
- base release compatibility remains outside the automated test loop.

This is acceptable for the first gate. It should be described as a release-regression gate, not as scientific
validation.

### 4. Configuration duplication is now more urgent

The response is correct that `tests/test_config.json` adds another model configuration representation.

The current set now includes at least:

- backend `models.json`;
- Dockerfile `ENV` / build args;
- `PARAM_ENV_MAP`;
- `tests/test_config.json`;
- planned `models.yml`.

The new test manifest is justified as an interim step. It should not become permanent architecture. The next
architecture task should be a canonical `models.yml` that either generates or validates the others.

The goal should be machine-enforced consistency, not another manually synchronized file.

### 5. Runtime-contract cleanup remains open

The earlier shared-base concerns still stand:

- CDC still defaults to Lambda mode;
- common Lambda/extraction code still carries Ryan White assumptions;
- `test-batch` still appears to reference `plotting/batch_dependencies.R` while the repo has only a
  `.backup` file at that path;
- shared trim behavior remains model-specific.

This is not necessarily blocking for the current gate, because the gate exercises the supported `run` path.
But it is still framework debt. A shared base image should not advertise modes that are unsupported,
model-specific, or known broken.

### 6. Provenance hardening is partial

The `fetch_simset.R` retry/resume/size verification change is useful and directly relevant to CI stability.

Still open:

- `version.sh` should print `JHEEM_ANALYSES_REF`;
- Actions should be pinned to SHAs if the team wants stronger supply-chain reproducibility;
- AWS CLI download/install should be checksummed;
- MSA workspace source should be pinned by digest;
- external data immutability remains a larger provenance concern.

The direction is right. The provenance story is not complete.

### 7. Repository hygiene needs one small cleanup before merge

The branch currently tracks Python bytecode cache files under `tests/__pycache__/`.

Those should be removed from git and ignored before merge. This is not a functional blocker, but it is a
basic hygiene issue and will otherwise create avoidable binary churn.

## Recommended next sequence

I would sequence the remaining work as follows:

1. Remove tracked `tests/__pycache__` files and add Python cache patterns to `.gitignore`.
2. Make the merge/release process explicit: PR fast checks versus required full gate runs.
3. Implement the true base digest cascade:
   - build candidate base;
   - pass the candidate base digest into model builds;
   - build model candidates from that base digest;
   - run the same model-output gate;
   - promote the coherent tested set.
4. Move toward canonical `models.yml`:
   - generate or validate Docker ENV;
   - generate or validate `PARAM_ENV_MAP`;
   - generate or validate test config;
   - validate backend `models.json`.
5. Recover legacy namespaced tags before old repos are archived.
6. Clean the runtime contract so supported modes are explicit per model.
7. Continue provenance hardening.

## Merge guidance

I would be comfortable reviewing this as a meaningful PR. I would not block it on every remaining framework
item.

I would block or request changes on:

- tracked `__pycache__` files;
- unclear process around whether the slow gate is required before merge/release;
- any wording that claims the base/model cascade is solved.

I would not block on:

- full `models.yml` implementation;
- all provenance hardening;
- runtime-contract cleanup;
- historical tag recovery;

provided those are tracked as explicit follow-up work and not described as closed.

## Final assessment

This branch materially improves the repo. The team responded to the core review feedback with working
infrastructure rather than just documentation.

The main thing to preserve now is precision. The project has a credible digest-based gate for model image
promotion. It does not yet have an automated candidate-base cascade or a single canonical configuration
source. Those are the next architectural steps.

If the team keeps those boundaries explicit, this is a solid direction and a significant improvement over
the original Phase A scaffold.
