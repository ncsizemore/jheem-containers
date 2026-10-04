# SHIELD container: administrator runbook

Operators should use
[Trying the SHIELD container](https://github.com/tfojo1/jheem_analyses/blob/master/applications/SHIELD/CONTAINER-PILOT.md)
in the analyses repository. They need only that guide and the installed
`shield-run.sh`, not a checkout of this repository. This page covers installation
and maintenance; the [technical README](README.md) describes builds and tests.

## Scope and selected image

This is a single-chain pilot, not a replacement for a full calibration. Stage 3
is refused, and handing pilot outputs to native stage 3 is not validated. Do not
delay ordinary calibrations or change users' R installations/source checkouts.

Use the retained
[`shield-pilot-2026.10.01-r36815091235` release](https://github.com/ncsizemore/jheem-containers/releases/tag/shield-pilot-2026.10.01-r36815091235).
It contains analyses `06505412ff4ad870ba0263361b791ba5d53737de`, integrated via
`3f463e2a`. It excludes the later screening-modifier change `3f9e2019` and
transmission-prior change `207672f2`. This is an operational test snapshot,
not an implicit choice for the next scientific calibration. The installed wrapper
can use a newer committed analyses checkout without rebuilding this image: it
preserves a separate source snapshot for each calibration code. See
[source selection and retention](SOURCE-SNAPSHOTS.md). This does not change the
pinned manager defaults or package versions.

Archive SHA-256:
`01e344d5948945851f397a41e2ec24b5f77878e2335b5d8960eb5a5a3a81e60c`.
Image ID:
`sha256:06e81402fbff908260a5a8237f0c5b9f7c3b20361604e1c855160ae7c0bb0c95`.
`IMAGE.txt` records both and the source revisions. The archive is about 1.9 GB;
each user's rootless loaded image takes roughly 4 GB of local storage.

## Prepare a current-runtime installation

Keep the October 1 installation above unchanged. A new dated pilot release is
a separately tested runtime, not an in-place update or automatic scientific
selection. Select its exact release tag from the acceptance record, and check
that its hosted canary and actual-stage-1 handoff both passed. New exports use a
unique image tag so rootless loading cannot take over the older pilot's tag.

From the clean container checkout used for the wrapper, set
`SHIELD_PILOT_RELEASE` to that dated release tag, then prepare fresh staging:

```bash
SHIELD_STAGE=$(mktemp -d)
mkdir -p "$SHIELD_STAGE/image"
gh release download "$SHIELD_PILOT_RELEASE" --repo ncsizemore/jheem-containers \
  --pattern jheem-shield-recorded.tar.gz --pattern IMAGE.txt \
  --dir "$SHIELD_STAGE/image"
python3 workloads/shield/tests/prepare_inputs.py "$SHIELD_STAGE/cache" --profile september-2026
python3 workloads/shield/installation_profile.py prepare "$SHIELD_STAGE"
cp workloads/shield/shield-run.sh workloads/shield/source_snapshot.py \
  workloads/shield/installation_profile.py workloads/shield/check_source_compatibility.R "$SHIELD_STAGE/"
git rev-parse HEAD
```

`prepare` checks the archive checksum and its unique tag, verifies both managers
against their resolution records, and writes an exclusive `installation.json`.
It refuses an existing profile. Confirm its image ID, source refs, input tags and
digests against the hosted reports and release record, not merely a successful
download. This profile selects September 9 syphilis and August 26 census inputs;
it is not a decision that they suit every scientific analysis.

Install these files into a **new** root-owned `root:jheem` directory, never over
`/home/jheem-shared/shield-container`. Preserve the permissions, ACL checks,
SELinux labeling, and account checks below. Copy `installation.json` and all
three Python/R helpers with the wrapper. Record wrapper and image-build refs
separately. The wrapper defaults to its own directory and the profile's
`/mnt/jheem_nas_share/tmp/shield-container-r<workflow-run>/<username>/` output
root; operators need no manager/image overrides. A different output root or seed
is an explicit run choice, not an edit to the installed profile.

After installation, use that directory's wrapper for setup and an isolated
administrator smoke before inviting an operator. Continue an older run through
its original installation and output root. No symlink, alias, default, package,
manager cache, or active calibration is switched automatically.

## Original October 1 installation (reference)

Target shield2 first. Check current jobs, memory, disk space, Podman, and the
actual NAS mount (`findmnt -T /mnt/jheem_nas_share`). Do not create state under
an unmounted NAS path or stop existing jobs. Inspect the proposed installation
before writing: never replace an installation used by active runs.

From a clean container-repository checkout, prepare new staging files:

```bash
SHIELD_STAGE=$(mktemp -d)
mkdir -p "$SHIELD_STAGE/image"
gh release download shield-pilot-2026.10.01-r36815091235 \
  --repo ncsizemore/jheem-containers \
  --pattern jheem-shield-recorded.tar.gz --pattern IMAGE.txt \
  --dir "$SHIELD_STAGE/image"
(cd "$SHIELD_STAGE/image" && grep ' jheem-shield-recorded.tar.gz$' IMAGE.txt | sha256sum -c -)
python3 workloads/shield/tests/prepare_inputs.py "$SHIELD_STAGE/cache"
cp workloads/shield/shield-run.sh "$SHIELD_STAGE/shield-run.sh"
cp workloads/shield/source_snapshot.py "$SHIELD_STAGE/source_snapshot.py"
cp workloads/shield/check_source_compatibility.R "$SHIELD_STAGE/check_source_compatibility.R"
git rev-parse HEAD
```

Check the archive/image identities against the values above as well as
`IMAGE.txt`. The preparer verifies the pinned census (`data-managers-v2026.08.26`)
and syphilis (`syphilis-manager-v2026.07.27`) inputs, without modifying ordinary
caches or promoting managers.

Install the verified `image/`, `cache/`, wrapper, and its helpers into the new shared
directory `/home/jheem-shared/shield-container`. Use administrator/root ownership
and group `jheem`: directories `0750`, data `0640`, wrapper `0750`. Check inherited
ACLs from the shared parent: operators should read/execute these files, not
replace the wrapper, cache, or `IMAGE.txt`. Record the wrapper's commit separately
from the image build. Outputs belong in the separate, per-user state root
`/mnt/jheem_nas_share/tmp/shield-container/<username>/`.

Label the installed local cache and `check_source_compatibility.R`
`container_file_t`, using persistent host
file-context policy where available. Never relabel CIFS. NAS access requires
`virt_use_samba` enabled on the host (`sudo setsebool -P virt_use_samba on`);
it was enabled for the earlier shield2 pilot, so verify before changing it.
The wrapper uses `--group-add keep-groups` and disables container networking.

For each intended user, verify `jheem` membership and enable lingering with
`sudo loginctl enable-linger <username>`. Confirm with
`loginctl show-user <username> -p Linger`. Lingering lets jobs survive logout.
Check home storage, rootless Podman support, input readability, and NAS writes.
Do not disable lingering or the NAS boolean while other containers depend on them.

## Verify before inviting operators

Use the installed wrapper as a non-root administrator, with a unique isolated
state root. These examples require a fresh directory chosen for this exercise:

```bash
export SHIELD_STATE_ROOT=/mnt/jheem_nas_share/tmp/shield-container/ADMIN-HANDOFF-TEST
cd /path/to/clean/committed/jheem_analyses
/home/jheem-shared/shield-container/shield-run.sh setup
/home/jheem-shared/shield-container/shield-run.sh start C.12580 container.smoke.stage0
/home/jheem-shared/shield-container/shield-run.sh status
/home/jheem-shared/shield-container/shield-run.sh logs C.12580 container.smoke.stage0
# After completion, verify its recorded outputs without rerunning the stage:
/home/jheem-shared/shield-container/shield-run.sh pipeline C.12580 container.smoke.stage0
```

Inspect the summary, simset, and input/output/attempt records. Confirm a detached
container survives logout. `status` says `outputs recorded (not rechecked)`;
only pipeline completion checks verify the referenced files and requested inputs.

Check each intended account's installed-file access, NAS write access, image
loading, and lingering. Authorized administrator account checks are not an
independent operator exercise; do not launch scientific calibrations as them.
Record host/date, image ID, wrapper commit, users checked, output root, and
results in the private server log. Invite users only for verified steps and
state outstanding checks explicitly. A representative full-stage run remains
separate from this short installation check.

## Recovery and updates

- Preserve failed state and records. Resume requires a checkpoint and matching
  inputs. If setup stopped earlier, investigate and choose a new
  `SHIELD_STATE_ROOT`; do not delete receipts to force a restart.
- Keep that state-root setting for subsequent commands. `status` lists the
  account's containers in that root, not other accounts' jobs. Startup locks
  serialize launches of the same location/code, but are not lifetime locks
  against arbitrary or cross-account writers. Keep run roots per-user.
- New calibration codes capture the committed checkout used at first launch;
  existing codes retain their source, image, manager tags, and seed. A pipeline
  selects its stages together. Preserve `run_sources/` with records and results.
  Reusing a code for a deliberately different experiment requires a new state
  root. Do not edit the selection registry to switch an existing run's source.
- A source-compatibility failure does not launch MCMC. Fix or choose source with
  its owners, then use a new state root for a different selection. A compatibility
  pass is not scientific validation. New package/dependency requirements may
  require a tested image: use the CI `jheem_analyses_ref` input with a full SHA,
  pass the canary, and retain that exact image before its Actions artifact expires.
- A killed launcher can leave `run_locks/` or `run_sources/.selection-lock`.
  Confirm that no launcher or run is active and preserve evidence before an
  administrator removes the specific abandoned lock; never clear locks blindly.
- Install another candidate separately. Do not retag/replace active users'
  images or change inputs beneath a checkpointed run. Do not automatically
  delete stopped containers or outputs: they may hold diagnostic evidence.

Retaining the runtime does not archive its scientific outputs or run records.
Automatic archival, full-stage validation with this image, multi-chain support,
and deterministic replay remain separate work.
