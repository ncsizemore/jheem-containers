# Analysis source snapshots

`shield-run.sh` separates the installed runtime (R and packages in the image)
from analysis code selected for a calibration. First use of a new calibration
code captures the clean committed checkout under the current working directory,
or `SHIELD_SOURCE_DIR` if supplied. It never pulls, installs packages, edits the
checkout, or silently ignores uncommitted changes. Local commits are supported.

## Selection and continuation

Selections are scoped to `SHIELD_STATE_ROOT`, keyed by calibration code rather
than location. All locations of a code therefore use the same code, image,
manager releases, and seed. A pipeline selects all requested codes together.
If any have a saved selection it is reused for the rest; conflicting saved
selections are rejected. For sequential stages, launch the complete pipeline
first so the selection covers all stages before the checkout changes.

Different new calibration codes may capture newer code without an image build.
To reuse an existing code with changed source or inputs, choose a new state root
and keep that setting for all subsequent commands. No selection is overwritten.
Resume and repeated pipelines use saved code even if the original checkout is
gone or has moved. Explicit changes to seed or manager tags are refused for an
existing selection. The saved image ID must still be loaded; a new shared image
does not replace it. Existing pre-snapshot runs must use their original wrapper
and runtime; the new wrapper refuses to invent their missing source history.

## Stored evidence

`run_sources/selections.json` records each calibration's source-bundle identity,
image ID, dated managers, and seed. Each content-identified bundle contains:

- `source.tar`: Git's archive of the entire selected commit, without `.git` or
  ignored local caches. Git archive attributes apply.
- `jheem_analyses/`: its materialized files, mounted read-only at
  `/opt/run-source/jheem_analyses`.
- `source.json`: commit, archive SHA-256, and per-file SHA-256 inventory. The
  bundle's directory name hashes this metadata.

The wrapper verifies archive, metadata, and every source file before reuse.
Missing/changed files, additional files, symlinks, and submodules are refused.
New bundles and whole pipeline selections publish through atomic filesystem
operations. A selection lock prevents concurrent writers; an orphaned lock
after a hard kill requires inspection, not automatic deletion. Run records also
record the selected analyses commit and actual image, rather than attributing
the run to the image's baked analyses code. Keep `run_sources/` with run outputs;
automatic archival of this tree is not implemented.

The source directory and its alias inside the writable state mount are both
mounted read-only. This avoids exposing the snapshot for accidental writes from
inside the container. This is not a defense against an owner deliberately
rewriting all records and checksums on the host.

A whole-repository snapshot currently uses about 580 MiB for its archive and
materialized tree together; codes selecting the same source reuse that bundle
within one state root. CIFS can impose mount-wide permissions instead of honoring
per-file read-only modes. The read-only container mounts and pre-launch digest
checks apply on both local disk and CIFS. Capturing and verifying thousands of
source files on the NAS adds startup time; it does not run on each MCMC iteration.

## Compatibility and checks

Before detached sampling, the wrapper loads the selected specification,
likelihood definitions, and calibration registry against the image's installed
packages, and verifies the requested calibrations are single-chain. Failure
stops without launching MCMC. This checks startup compatibility, not all possible
model execution, scientific correctness, or deterministic replay. Model code may
require a new runtime when its package/API requirements change.

Fast tests (`pytest workloads/shield/tests -q`) exercise capture, moving and
missing checkouts, dirty source, integrity failures, conflicting pipelines,
legacy state, and explicit input changes. `tests/snapshot_calibration.R` supplies
two tiny calibration names absent from the retained image for a real-engine
source-overlay exercise; use it only in a separate committed test checkout.
Wrapper tests also verify both read-only mounts, selected source/image identity,
and refusal to launch after a failed compatibility check.

The wrapper retains stopped containers for diagnostics. Its launch lock covers
the startup window; the running-container check sees only the same account.
Cross-account writers to one run tree are still unsupported. Multi-chain stage 3
remains outside this pilot. The mounted source path must remain named
`jheem_analyses` because existing source calls use that relative layout.
