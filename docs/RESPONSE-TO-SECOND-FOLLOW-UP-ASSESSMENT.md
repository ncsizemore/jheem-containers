# Response to the Second Follow-up Assessment (after the gate)

**Date:** 2026-06-29
**Responding to:** `SECOND-FOLLOW-UP-ASSESSMENT-AFTER-GATE.md`
**From:** the migration/implementation session

## Agreed framing

Adopting your wording precisely: this is a **model-image promotion gate**, not a complete
base/model release gate. The base/model **candidate-base cascade** and a **canonical
configuration source** are the next architectural steps and are **not** done. We'll keep
that boundary explicit in all future language.

## The three things you'd block on — addressed

1. **Tracked `__pycache__`** — removed from the index; `__pycache__/`, `*.py[cod]`,
   `.pytest_cache/` added to `.gitignore`. Tracked `tests/` is now source + config only.
2. **PR validation vs. the real gate** — the workflow now runs the **full** suite (smoke +
   golden + perturbation) on **every** event including PRs, not smoke-only. `select` already
   scopes builds to release-impacting paths, so a docs-only PR builds/tests nothing and a
   model PR runs that model's full gate — PR cost equals blast radius. A green PR now means
   the model-output gate actually ran. The policy is written down in `tests/README.md`
   (the "When the gate runs" table). Promotion remains push-to-`main`/tags only, on the
   tested digest, fail-closed.
3. **Over-claiming** — see the framing above and the explicit open list below. We are not
   describing the cascade, canonical config, runtime cleanup, or full provenance as closed.

## Open follow-ups — tracked, NOT closed

| Item | Status |
|------|--------|
| **Base-image compatibility (true candidate-base digest cascade)** | **Open** (Phase B). Base test is a no-op for model compat; a base change isn't proven against downstream models in CI. The manual `base:1.6.2` cascade we ran is the design spec, not the automation. |
| **Canonical `models.yml`** | **Open — top architecture priority.** Five representations exist (`models.json`, Dockerfile ENV/args, `PARAM_ENV_MAP`, `test_config.json`, planned `models.yml`); goal is generate-or-validate with machine-enforced consistency. |
| **Runtime-contract cleanup** | **Open.** CDC default `CMD ["lambda"]`; RW assumptions in common lambda/extraction; `test-batch` references `plotting/batch_dependencies.R` (only `.backup` present); model-specific `trim_simsets.R`. |
| **Legacy namespaced tag recovery** | **Open** — must precede archiving the five source repos. |
| **Provenance hardening** | **Partial.** Done: `fetch_simset.R` retry/resume/verify (`base:1.6.2`). Open: `version.sh` print `JHEEM_ANALYSES_REF`; pin Actions to SHAs; checksum AWS CLI; pin MSA workspace by digest; external-data immutability. |
| **PR change-detection** | **Fixed (3rd-round follow-up).** `pull_request` now diffs against the **merge base** with the target branch (`merge-base FETCH_HEAD <pr-head>`), fail-safe to ALL if unresolved — so a multi-commit PR is no longer under-selected. Dry-run confirmed: a PR with `models/cdc-testing/` in commit 1 + docs in commit 2 now selects `cdc-testing` (old `HEAD~1` selected nothing). This makes "a green PR means the model-output gate ran" defensible. |
| **Perturbation coverage** | **Open enhancement.** One configured parameter per model today; should become every parameter (make `perturb` a list). |
| **Base-version spread** | **Intentional interim.** MSA on `1.6.0`, heavy models on `1.6.2`; full consistency is a later cleanup. |

These are scientific-validation-adjacent only where noted: the suite is a **release-regression
gate** (reproduction + parameter plumbing), not scientific correctness — agreed.

## Process

Still **holding the PR/merge** until you've signed off. When opened, this is a model-image
gate PR with the above tracked as explicit, open follow-ups — not a claim that the release
framework is complete.
