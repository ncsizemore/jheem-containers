# Response to the Follow-up Assessment

**Date:** 2026-06-23
**Responding to:** `FOLLOW-UP-ASSESSMENT-OF-RESPONSE.md`
**From:** the migration/implementation session

## Headline

You set an explicit bar:

> "If the next work lands the digest-based gate and includes parameter-perturbation
> tests, I would be much more comfortable treating the monorepo as the operational
> source of truth for container releases."

That work is now **landed and validated in CI** — not designed, not sequenced. Below
is the evidence and an honest accounting of what this does and does **not** close.

## The gate is built and proven

`build.yml` is now **build → test-by-digest → promote**:

- **build** the candidate, push it, capture its **immutable digest**;
- **test** that *exact digest* — smoke (version/provenance, workspace) + the slow tier
  (golden regression + parameter perturbation);
- **promote** re-tags the **tested digest** to `:latest`/semver via `imagetools create`
  — **no rebuild between test and promotion**.

Validated end-to-end:

```
All 5 models — build → test-by-digest → green:
  cdc-testing      4 passed (39:25)   golden + PERTURBATION both ran
  ryan-white-ajph  4 passed (32:41)
  ryan-white-croi  4 passed (31:35)
  ryan-white-msa   4 passed
  base             smoke passed

Promote-by-digest:  base-v1.6.2 -> build -> test -> promote: success -> base:1.6.2 live
Fail-closed:        the broken iterations correctly SKIPPED promote (nothing published)
```

## Point-by-point against your "what remains open"

**1. Test/promotion gate (your central missing piece) — CLOSED.** Built, and the
"promote the *tested* digest, never a rebuild" property is implemented via
`imagetools create` against the digest the test job consumed.

**2. CDC fix must become a permanent regression test — CLOSED.** The perturbation test
is in the gate and passed in CI:
`test_param_perturbation[cdc-testing] PASSED`. It asserts your exact contract — a
non-default `proportion_tested_regardless` **moves the intervention** while **baseline
is unchanged** (proving the param reaches `PROPORTION_TESTED`). Null-vs-value is handled
in the comparator as a mismatch, not a silent skip, per your list.

**7. Branch/doc hygiene — CLOSED.** Both review documents are now tracked (the response
references them); all work is on a PR branch; and per your recommendation we are
**holding the PR/merge until you've reviewed** — `main` is not gating, nothing is
published to `:latest`.

**6. Provenance hardening — PARTIAL.** `fetch_simset.R` now does retry/resume/verify
(shipped as `base:1.6.2`); that one was forced onto the critical path (see below).
Still open: `version.sh` printing `JHEEM_ANALYSES_REF`, and pinning Actions/AWS-CLI/the
MSA workspace by digest.

**4. Runtime-contract cleanup — STILL OPEN.** The broken/model-specific modes (CDC
default `CMD ["lambda"]`, `test-batch`, CROI-specific `trim_simsets.R`) are untouched.

**5. Historical tag recovery — STILL OPEN.** We added `base-v1.6.2` (which *demonstrates*
the namespaced scheme), but the legacy tags from the five source repos are not yet
recreated. This still must happen before archiving them.

**3. `PARAM_ENV_MAP` is a patch, not the architecture — STILL TRUE, and now sharper.**
You were right, and we made it more so: the gate added `test_config.json`, a *fourth*
representation of per-model config (alongside `models.json`, the Dockerfile ENV, and the
param map). The gate works, but this raises the priority of your recommendation — one
canonical `models.yml` that **generates or validates** the others. We're treating that
as the next architectural item, explicitly to stop the copy count from growing.

## What the gate-building taught us (your cascade point, in practice)

Landing the gate walked straight into your P0 cascade finding. The download fix lives in
`base/common/` — so it only reaches the models once the **base is rebuilt and the models
rebuild `FROM` it**. The gate's Phase-A fan-out builds models from the *published* base in
parallel, so it could not validate the base change in one run. We did the cascade
**by hand**: cut `base:1.6.2` → bump the heavy models' `BASE_VERSION` → rebuild → green.
That manual sequence is exactly the spec for the **Phase B automated digest cascade**
(build candidate base → pass its digest into model builds → test → promote together).
So your cascade finding is now not just accepted but *experienced*.

## Honest residual list

- **Phase B true digest cascade** — still fan-out; the manual cascade above is the design,
  not the automation.
- **`models.yml` canonical** — now the top architectural priority (copy count grew to 4).
- **Runtime-contract cleanup**, **legacy tag recovery**, **`version.sh` provenance**,
  **Actions/AWS/workspace pinning** — open.
- **PR path-selection** — we broadened the filter (a `tests/` or `.github/` change rebuilds
  all) and a no-op now shows as *skipped* (visibly distinct from a validated pass), but the
  PR diff still falls back to `HEAD~1` rather than the merge base. Partial.
- **Base-version spread** — MSA stays on `1.6.0`, the heavy models on `1.6.2` (MSA's small
  simset doesn't need the fetch fix). Intentional interim; full consistency is a cleanup.

## Net

Your #1 is done and demonstrated, including the specific test that would have caught the
original bug. We're not claiming "safe and finished" — several of your items remain open,
and we added one config-copy debt we now have to pay down. But the release mechanism you
were waiting on exists, gates by digest, fails closed, and is proven across all five
models. We're holding the merge for your read before `main` starts gating.
