# Golden regression artifact

`golden/FL_a50-o30-r40.json` is the production custom-sim artifact for this model
(CloudFront `/ryan-white-state/custom/FL/a50-o30-r40.json`), preserved as the
reproduction reference.

**Validated 2026-06-19:** the rocker-based official image
(`ghcr.io/ncsizemore/jheem-ryan-white-ajph:latest`, base 1.6.1) reproduces this
golden **bit-for-bit** — incidence/sex slice, baseline + intervention, max abs
diff `0.0`:

```
docker run --rm -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-ryan-white-ajph:latest \
  run --location FL --param adap_loss=50 --param oahs_loss=30 --param other_loss=40 \
      --out /out/results.json
```

The comparator + runner are deliberately **not** duplicated here. The cross-model
regression suite (pytest, parametrized over all models) will live in the planned
container monorepo — see jheem-portal `REPRODUCIBILITY-AND-CITATION-PLAN.md`
§5c (testing) and §5e (monorepo). This file just preserves the golden until then.
