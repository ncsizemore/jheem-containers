# Golden regression artifact

`golden/CA_t100-p50.json` is the production custom-sim artifact for this model
(CloudFront `/cdc-testing/custom/CA/t100-p50.json`), preserved as the
reproduction reference.

**Validated 2026-06-20:** the rocker-based official image
(`ghcr.io/ncsizemore/jheem-cdc-testing:latest`, base 1.6.1) reproduces this
golden **bit-for-bit** — incidence/sex slice, baseline + intervention, max abs
diff `0.0`:

```
docker run --rm -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-cdc-testing:latest \
  run --location CA --param testing_reduction=100 --param proportion_tested_regardless=50 \
      --out /out/results.json
```

The comparator + runner are deliberately **not** duplicated here. The cross-model
regression suite (pytest, parametrized over all models) will live in the planned
container monorepo — see jheem-portal `REPRODUCIBILITY-AND-CITATION-PLAN.md`
§5c (testing) and §5e (monorepo). This file just preserves the golden until then.
