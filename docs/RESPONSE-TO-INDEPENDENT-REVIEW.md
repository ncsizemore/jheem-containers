# Response to the Independent Monorepo & Container-Framework Review

**Date:** 2026-06-23
**Responding to:** `INDEPENDENT-MONOREPO-AND-CONTAINER-FRAMEWORK-REVIEW.md`
**From:** the migration/implementation session

## Overall

This was a high-value review — not a confirmation pass. It independently ran the images, traced the
config contracts, and caught several real defects, including one we'd have shipped. We accept most of it,
have already fixed the concrete correctness issues, and have sequenced the rest. Two places we'd reframe
(severity, not substance) are noted explicitly. The single most valuable contribution is conceptual: the
distinction between *computational regression equivalence* and *scientific correctness* — we'd been
leaning on the goldens harder than that distinction allows, and we're adopting it.

## Disposition summary

| Finding | Disposition |
|--------|-------------|
| P0 — cascade doesn't use newly-built base | **Accept substance; reframe severity** (Phase B scope, not a Phase A defect; our overstated claim corrected) |
| P0 — images not gated by golden/smoke tests | **Accept** — the key actionable gap; building the gate next |
| P0 — batch extraction can publish partial sets | **Clarify** — fail-open is intentional; accept the *silent*-gap concern; their manifest+allowlist reconciles both (inherited/backend) |
| P1 — misleading green from path selection | **Accept** — real bugs in our select logic; sequenced |
| P1 — cache-cold builds use mutable inputs | **Accept** — mostly already tracked (OneDrive = §5d); sequenced |
| P1 — base advertises model-specific/dead modes | **Accept** — real and **inherited**; sequenced |
| P1 — historical tags not preserved | **Accept** — our miss; recreate namespaced tags before archiving |
| P1 — `models.yml` as another source of truth | **Accept the principle strongly** — the param bug is an instance of it |
| Add'l — size/privilege, unpinned tooling, narrow goldens, permissive matching, governance | **Accept**; sequenced (several are existing Tier-3 / Tier-1 items) |
| Research — regression ≠ correctness; archival vs operational images | **Strongly affirm; adopt** |

## Already fixed (committed)

- **CDC parameter silently ignored.** Root cause confirmed: the `run` wrapper uppercased `--param` keys to
  env vars, which matches the model contract for the RW models *by coincidence* (`adap_loss→ADAP_LOSS`) but
  is wrong for CDC (`proportion_tested_regardless→PROPORTION_TESTED`, not `…_REGARDLESS`). Fixed by
  resolving through a baked `PARAM_ENV_MAP` (the canonical `id→envVar` map from `models.json`), with
  UPPERCASE fallback. **Validated with the review's own perturbation method:** the fixed wrapper at `p=30`
  moves the CDC intervention trace by 193.5 vs the `p=50` golden, baseline unchanged (`0.0`) — the
  parameter now reaches the model. (Production was never affected; the backend maps via the `envVar` field.)
- **OCI `image.source` labels** on all five Dockerfiles repointed from the old per-repo URLs to
  `jheem-containers`.
- **Overstated "cascade" claim corrected** (see below).
- **Root README** "in progress" → Phase A done.

## Accepted and sequenced

- **CI test/promotion gate (P0).** The most important item. We validated the goldens *out of band*; the
  workflow does not gate on them. We will implement the recommended **build-candidate-digest → smoke +
  shared four-model golden suite → promote** pipeline, with no rebuild between test and promotion. The
  shared suite will adopt the review's golden-coverage recommendations directly: **non-default parameter
  values + perturbation tests** (exactly what would have caught the CDC bug), multiple outcomes/facets,
  treating `null`-vs-value as a failure, duplicate-key detection, and recording image/input digests.
- **CI selection bugs (P1).** Compare PRs against the merge base (not `HEAD~1`); make a no-op build
  *distinct* from a validated one; and generate the matrix from the canonical manifest rather than the
  current hardcoded shell list.
- **Tag namespacing (P1).** Our own plan called for it and we skipped it in the `filter-repo` merge.
  We will recreate namespaced legacy tags (`base/v1.6.1`, `ryan-white-msa/v1.0.1`, …) **before** archiving
  the source repositories.
- **Runtime-contract cleanup (P1).** Remove/relocate the non-generic shared-base modes; make the default
  command safe (the CDC `CMD ["lambda"]` failure is real); define supported modes per model and test them.
- **Provenance hardening.** `version.sh` to print `JHEEM_ANALYSES_REF`; `fetch_simset.R` retry/resume +
  checksum; pin the MSA workspace source by **digest**; pin Actions to SHAs and checksum the AWS CLI;
  consider date-pinned package snapshots. (OneDrive immutability is the largest item and is tracked
  separately — see below.)
- **`models.yml` as the canonical schema** that *generates or validates* the downstream representations,
  with single ownership and machine-enforced cross-repo consistency — not a fifth drift surface. The CDC
  param bug is precisely the failure mode this prevents.
- **Governance metadata** (LICENSE, `CITATION.cff`, contribution/security/ownership) — which also serves
  the citation goal in the reproducibility plan.

## Where we'd reframe (severity, not substance)

**The cascade finding is correct but it is Phase B scope, not a Phase A defect.** Phase A's explicit
contract was *identical behavior, relocated* — and the existing (polyrepo) behavior is precisely "models
pin a published base." So "fan-out, not a true cascade" is accurate, but it describes a deliberate Phase A
boundary, not a regression. The actual error was **ours, in the documentation** ("restores the cascade"),
which we've corrected. The review's *compatibility-fan-out vs. release-fan-out* distinction is exactly the
right design input for the Phase B digest cascade — particularly because MSA's `jheem2` constraints differ
from the state models', so "test all against a candidate base" and "release all onto it" must be separate.

**Inherited vs. introduced.** Most P1s (broken modes, partial-result fail-open, image size, mutable
inputs) are long-standing framework debt the migration *relocated as-is*, not defects it introduced. That
doesn't reduce their validity — the review fairly covers the whole framework — but it matters for triage
and ownership: the migration-introduced set (the param bug, the tag-namespacing miss, the overstated
claim) is small and now largely closed.

## Clarification: the partial-result behavior is intentional

`batch_plot_generator.R` continues past a missing scenario by design — we did not want a legitimately
unavailable data facet to fail an otherwise-valid run. We accept the review's deeper point that *silent*
incompleteness is dangerous. Crucially, the review's own recommendation reconciles with our intent: it is
not "fail on any missing," it is **validate against an expected-output manifest with an explicit allowlist
for known-unavailable combinations** — i.e. fail on *unexpected* gaps only. We'll adopt that synthesis.
This lives in the backend custom-sim pipeline, so it's sequenced outside the monorepo work.

## What we strongly affirm

- **Regression equivalence ≠ scientific correctness.** The four bit-for-bit goldens prove the rebuilds
  reproduce the *published behavior* — which is exactly what reproducibility requires, and says nothing
  about whether that behavior is correct. We will pair the goldens with domain-aware contracts (parameter
  boundary behavior, no-intervention ≡ baseline, nonnegativity/valid ranges, each parameter provably
  affecting its quantity, deterministic repeatability). We've effectively started: the perturbation test
  used to validate the param fix *is* one of these.
- **Archival vs. operational images.** We'll formalize this: archival/manuscript artifacts are immutable
  by digest and never silently rebuilt under the same identity; operational images receive updates. This
  dovetails with the citation/Zenodo direction in the reproducibility plan.

## Relationship to existing plans

Much of the backlog is *accept-and-fold* rather than net-new: OneDrive immutability is the data-provenance
gap already tracked (reproducibility plan §5d) and gated on a separate data-manager CI pipeline owned by
another teammate; image hardening (multi-stage, non-root) and digest-pinning are existing Tier-3 items;
governance/citation metadata is Tier-1. The review's value is that it ties these to concrete container
defects and supplies a clean sequencing (make Phase A trustworthy → close provenance → clean the runtime
contract → recover metadata → then Phase B), which we are adopting.

## Net

Agreed direction, with the cascade reframed as Phase B's job and a correctness-first ordering. The concrete
bugs are fixed; the trust gate (test-by-digest + the shared golden suite) is the next focused effort and
the right thing to land before Phase B.
