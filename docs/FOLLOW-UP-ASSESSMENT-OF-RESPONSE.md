# Follow-up Assessment of the Response to the Independent Review

**Date:** 2026-06-23  
**Responding to:** `RESPONSE-TO-INDEPENDENT-REVIEW.md`  
**Perspective:** independent follow-up review after reading the response and lightly checking the repo state

## Bottom line

The response is strong. It is candid, technically grounded, and does not try to minimize the important
findings. The migration session correctly distinguishes between defects introduced by the migration and
pre-existing framework debt, while still accepting responsibility for sequencing the remaining work.

That said, the current state is best described as:

> A promising and improved Phase A, with one real correctness bug fixed and a much clearer recovery plan,
> but not yet a trustworthy release system.

The next decisive step is still the test/promotion gate. Until candidate images are tested by digest before
promotion, the monorepo can build and publish images, but it cannot yet prove that what it publishes is
behaviorally safe.

## What is materially better now

### 1. The response accepts the core findings

The response does the right thing in tone and substance. It accepts the main issues rather than arguing
around them:

- image publication is not yet gated by model-output tests;
- path selection can produce misleading green workflows;
- mutable external inputs remain a reproducibility risk;
- the shared runtime contract still contains model-specific assumptions;
- historical tags need namespaced recovery;
- `models.yml` should become canonical rather than another copy of configuration;
- regression equivalence is not the same thing as scientific correctness.

This is a healthy posture. The response reads like a team using review feedback to sharpen the system,
not simply close tickets.

### 2. The CDC parameter bug appears fixed

The original review called out a mismatch between the CLI-facing CDC parameter
`proportion_tested_regardless` and the environment variable actually consumed by the model,
`PROPORTION_TESTED`.

The local repo now has a committed fix in `base/common/run_simulation.sh`: `--param` keys are resolved
through a baked `PARAM_ENV_MAP`, with uppercase fallback. The CDC Dockerfile now maps:

```text
proportion_tested_regardless=PROPORTION_TESTED
```

That is a real improvement, and it addresses the concrete bug. The response also reports that the fix was
validated with a perturbation test: changing the CDC intervention parameter moved the intervention trace
while leaving baseline unchanged. That is exactly the kind of test that should become part of the gate.

The caution: this currently appears to be a code fix plus out-of-band validation, not yet a committed
regression test in CI. So the bug is corrected, but the class of bug is not yet prevented.

### 3. The documentation overclaim was corrected

The response fairly reframes the cascade finding. The current Phase A behavior is essentially the old
polyrepo behavior relocated into a monorepo: model images pin a published base image, rather than consuming
the newly built candidate base from the same workflow run.

That is acceptable as a Phase A boundary, provided the docs do not claim a true base-to-model cascade. The
README has now been adjusted to describe Phase A as relocation plus matrix CI, with Phase B and the
test/promotion gate still pending.

This is a good correction. It keeps the team from accidentally relying on guarantees the current workflow
does not provide.

### 4. The response correctly embraces the research-computing distinction

The strongest part of the response is its acceptance of this distinction:

- bit-for-bit goldens demonstrate reproduction of published behavior;
- they do not demonstrate scientific correctness.

That distinction matters a lot here. These containers sit at the boundary of software infrastructure and
scientific inference. The proposed next layer of tests — parameter perturbation, boundary behavior,
nonnegativity/range checks, deterministic repeatability, and “no intervention equals baseline” contracts —
is the right direction.

## What remains open

### 1. The test/promotion gate is still the central missing piece

The existing workflow still builds and pushes images without running the golden/smoke suite as a promotion
gate. This remains the highest-priority engineering gap.

The desired structure is:

1. build candidate image;
2. record the candidate digest;
3. run smoke tests and model-output regression tests against that exact digest;
4. promote that same digest to semver/latest tags only if tests pass.

The important detail is “no rebuild between test and promotion.” If the system tests one image and publishes
another, the gate is weaker than it looks.

Until this exists, Phase A can be useful, but it should not be treated as a reliable release mechanism.

### 2. The CDC fix needs to become a permanent regression test

The CDC parameter bug is a useful warning shot. It is exactly the sort of issue that a bit-for-bit default
golden can miss, because default or near-default parameter values may not exercise the contract deeply
enough.

The CI suite should include at least one CDC perturbation test that proves:

- `proportion_tested_regardless` reaches `PROPORTION_TESTED`;
- changing it changes the relevant intervention output;
- baseline remains unchanged when only intervention parameters are varied;
- `null` versus present values are treated as meaningful differences, not silently skipped.

This should be one of the first tests added to the promotion gate.

### 3. `PARAM_ENV_MAP` is a good patch, not the final configuration architecture

The new `PARAM_ENV_MAP` is a practical short-term fix. It localizes the parameter mapping and avoids the
naive uppercase transform.

But architecturally, it is still copied configuration baked into each model Dockerfile. The long-term goal
should be exactly what the response says: one canonical model manifest that generates or validates the
Dockerfile environment, backend `models.json`, docs examples, and test expectations.

Otherwise the project risks turning this bug from “bad uppercase convention” into “stale copied env map.”

### 4. Runtime-contract cleanup is still open

The response accepts that the shared base still advertises model-specific or nonfunctional modes. That work
does not appear closed yet.

Examples that still matter:

- CDC still defaults to Lambda mode, even though the earlier review found that default command fails locally.
- Common Lambda/extraction code still contains Ryan White workspace assumptions.
- The `test-batch` mode references `plotting/batch_dependencies.R`, while the repo still appears to carry
  only a `.backup` file for that path.
- The shared `trim_simsets.R` remains effectively CROI-specific.

This is not necessarily a Phase A blocker if the team is only promising relocation equivalence. But it is a
real framework-design issue before the base image can honestly be considered model-agnostic.

### 5. Historical tag recovery is accepted but not done

The response correctly accepts that the monorepo merge lost information because tag names collided across
source repositories.

As of this follow-up check, namespaced tags such as `base/v1.6.1` or `cdc-testing/v2.1.2` do not appear to
exist yet. This should happen before archiving the old source repos, while the original tag intent is still
easy to verify.

### 6. Provenance hardening is still mostly backlog

The response lists the right provenance items: printing `JHEEM_ANALYSES_REF`, checksumming simset downloads,
pinning the MSA workspace source by digest, pinning Actions to SHAs, checksumming AWS CLI, and improving
external data immutability.

Those are the right moves, but they are still mostly future work. For example, `version.sh` still does not
print `JHEEM_ANALYSES_REF`.

This does not invalidate Phase A, but it does mean the reproducibility story remains incomplete.

### 7. The local branch state needs care before sharing/publishing

One practical housekeeping point: local `main` is currently ahead of `origin/main` by three commits:

- CDC parameter mapping fix;
- OCI label / README status fix;
- response document.

Also, the independent review document itself is still untracked locally, while the response document refers
to it. If the branch is pushed without adding the review doc, the response will point to a file that is not
actually in repo history.

I would not push this directly to `main` unless the team is comfortable with the current workflow publishing
images before the new gate exists. A PR branch is safer for review and avoids accidental release semantics.

## Assessment of the response's reframing

The cascade reframing is fair.

The original review was right that the current workflow performs fan-out activity, not a true candidate-base
cascade. The response is also right that this is not necessarily a Phase A regression if the explicit Phase
A goal was behavior-preserving relocation.

The key is language discipline. Current Phase A should be described as:

> monorepo relocation, matrix build, and preservation of existing image names/behavior.

It should not be described as:

> validating that all model images work against a newly built base candidate.

That latter guarantee belongs to Phase B or to the test/promotion gate.

The inherited-versus-introduced distinction is also fair. Many issues are not new defects caused by the
monorepo migration. But the migration is still the right moment to expose and prioritize them, because a
monorepo makes shared contracts more explicit.

## Recommended next sequence

The response's proposed ordering is mostly right. I would make the immediate order very explicit:

1. Put both review documents under version control, or keep both out. Avoid committing only the response.
2. Build the digest-based test/promotion gate.
3. Add the CDC perturbation test as a first-class regression test.
4. Fix CI path selection so “skipped” and “validated” are visibly different outcomes.
5. Recover namespaced historical tags before archiving old repos.
6. Make `models.yml` canonical by generating or validating Docker ENV, backend config, docs, and tests.
7. Clean up runtime modes and make supported commands explicit per model.
8. Continue provenance hardening and archival/operational image separation.

## Final perspective

The response improves my confidence in the team and the direction. It does not yet fully improve my
confidence in the release mechanism, because the central gate is still pending.

That is not a knock; it is just the honest line between “the team responded well” and “the system is now
safe.” The migration has moved from “initial scaffold with some hidden risks” to “credible Phase A with a
clear route to trustworthiness.”

If the next work lands the digest-based gate and includes parameter-perturbation tests, I would be much more
comfortable treating the monorepo as the operational source of truth for container releases.
