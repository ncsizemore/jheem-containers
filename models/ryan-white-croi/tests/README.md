# Golden regression artifact

`golden/CO_a50-o30-r40.json` is the production custom-sim artifact for this model
(CloudFront `/ryan-white-state-croi/custom/CO/a50-o30-r40.json`), preserved as the
reproduction reference.

**Validated 2026-06-21:** the rocker-based official image
(`ghcr.io/ncsizemore/jheem-ryan-white-croi:latest`, base 1.6.1) reproduces this
golden **bit-for-bit** — incidence/sex slice, baseline + intervention, max abs
diff `0.0`:

```
docker run --rm -v jheem-cache:/cache -v "$PWD/out:/out" \
  ghcr.io/ncsizemore/jheem-ryan-white-croi:latest \
  run --location CO --param adap_loss=50 --param oahs_loss=30 --param other_loss=40 \
      --out /out/results.json
```

This golden doubled as the arbiter for pinning `jheem_analyses` (CROI was built
from `HEAD` — unpinned): the rebuild on the traced commit `250ffc8a` reproduces
it exactly, confirming the pin.

The comparator + runner are deliberately **not** duplicated here. The cross-model
regression suite (pytest, parametrized over all models) will live in the planned
container monorepo — see jheem-portal `REPRODUCIBILITY-AND-CITATION-PLAN.md`
§5c (testing) and §5e (monorepo). This file just preserves the golden until then.
