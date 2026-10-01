# Running SHIELD in the container

This runs a SHIELD calibration inside a fixed, tested container instead of your
own R setup, so every run uses the same code, packages, and input data. You
control it with one script, `shield-run.sh`. Everything below is typed in a
terminal on the server, over SSH (not the RStudio terminal).

## Before you start

The server administrator does a one-time setup for you (see the end of this
page). After that, run this once:

```bash
/home/jheem-shared/shield-container/shield-run.sh setup
```

It checks everything is in place and loads the container (a few minutes the
first time). It ends with `Setup is complete.` To save typing, you can add a
shortcut:

```bash
alias shield-run=/home/jheem-shared/shield-container/shield-run.sh
```

The examples below use that shortcut.

## A quick test (about 2 minutes)

```bash
shield-run start C.12580 container.smoke.stage0
shield-run status
```

`container.smoke.stage0` is a tiny two-step test calibration for Baltimore.
While it runs, `status` shows `running`. After about 2 minutes it shows
`exited (exit 0)` with `checkpoints saved: 2`. `exit 0` means it finished
successfully.

## Running a real calibration

Use the location and calibration code you would normally use, for example:

```bash
shield-run start C.12580 calib.9.28.stage0
```

It keeps running if you log out or close your laptop. A stage takes many hours;
it saves a checkpoint every 500 iterations (about every 30 minutes for stage 0).

- **Progress:** `shield-run status` shows each run, whether it's running, how
  many checkpoints it has saved, and its latest output line.
- **Latest output:** `shield-run logs C.12580 calib.9.28.stage0`
- **Stop it:** `shield-run stop C.12580 calib.9.28.stage0`
- **Continue it later:** `shield-run resume C.12580 calib.9.28.stage0`. It picks
  up from the last saved checkpoint; work since that checkpoint is redone.

`start` always begins a new calibration and refuses if that calibration already
has saved results. Use `resume` for a checkpointed run; preserve failed setup
state for diagnosis and use a new state root for a deliberate restart. The
script refuses to run a calibration you're already running, but
it can't see other accounts' runs: don't run the same calibration for the same
location from two accounts.

## Running stages 0, 1 and 2 in one go

`pipeline` runs stages one after another, each starting when the previous one
finishes, as the usual phase 1 does:

```bash
shield-run pipeline C.12580 calib.9.28.stage0 calib.9.28.stage1 calib.9.28.stage2
```

Run one pipeline per location; different locations can run at the same time.
`shield-run status` lists each stage as `outputs recorded (not rechecked)`,
`checkpoints saved: N`, or `not started`. Re-running the pipeline verifies the
recorded files and requested inputs before skipping completed stages. `logs`
and `stop` take any of the pipeline's calibrations, for example
`shield-run stop C.12580 calib.9.28.stage1` stops the whole pipeline.

To continue a pipeline after a stop or a failure, run the same `pipeline`
command again: finished stages are skipped, the interrupted stage continues from
its last checkpoint, and the rest follow. If a stage fails, the later stages
don't run.

Stage 3 (four chains) can't run in the container yet; `start` and `pipeline`
refuse it. Existing native workflows remain available, but transferring this
pilot's isolated stage-2 outputs into a native stage-3 run has not yet been
validated. Arrange that handoff before relying on the pilot for a full analysis.

## Practice: stop and resume (about 1 hour)

This checks that an interrupted run continues where it left off.

1. `shield-run start C.12580 calib.9.28.stage0`
2. Wait until `shield-run status` shows `checkpoints saved: 1` (about 30 minutes).
3. `shield-run stop C.12580 calib.9.28.stage0`. `status` now shows `exited`.
4. `shield-run resume C.12580 calib.9.28.stage0`. `status` shows `running` again,
   and `shield-run logs C.12580 calib.9.28.stage0` shows it preparing to run the
   remaining iterations rather than all 15,000.
5. Either let it finish (about 14 hours) or stop it again.

## Where the results go

Everything is written to
`/mnt/jheem_nas_share/tmp/shield-container/<your username>/`, in the usual
layout:

- `mcmc_runs/shield/<calibration>/<location>/`: the calibration's checkpoints
- `mcmc_summaries/shield/<calibration>/`: the MCMC summary, when it finishes
- `simulations/shield/<calibration>-<n>/<location>/`: the simulation set
- `run_records/shield/<location>/<calibration>/`: the run's records:
  - `inputs.json`: exactly which code and data versions it used, and for stage
    1 or 2, which earlier stage's results it started from
  - `outputs.json`: fingerprints of the summary and simulation set it produced
  - `attempts/`: one small file per start or resume: who ran it, where, with
    which container, when, and how it ended

These are test locations while the container is being tried out; they don't
touch the team's usual `mcmc_runs`. Please don't edit or delete the
`run_records` files; they're how we can later tell which code and data produced
a result.

## If something goes wrong

- **`lingering is off`** or **`containers can't reach the NAS`**: the
  administrator setup isn't finished; send the message to the administrator.
- **`is already running`**: that calibration is still going; check `shield-run
  status`.
- **`single-chain calibrations only`**: that calibration is a stage 3 (four
  chains); run it the usual way for now.
- **`has no recorded outputs`**: a stage 1 or 2 needs the earlier stage to have
  finished in the container first; run the stages with `pipeline`.
- **`status` shows `exited` with a number other than 0:** run `shield-run logs
  <location> <calibration>` and send the last lines to whoever supports the
  container.
- **A `resume` fails straight away:** the run's saved inputs don't match, or
  there is no checkpoint yet. Send the `logs` output.
- **`completed stage ... failed verification`:** preserve the run tree and send
  the log. A record exists, but its files or requested inputs do not match.
  Nothing is automatically deleted or repaired.
- **Setup stopped before a checkpoint:** preserve the existing tree for diagnosis.
  A deliberate restart can use a new `SHIELD_STATE_ROOT`; do not delete records
  to force the existing run past its safety checks.

---

## Administrator setup (once per server, and once per user)

Per server, in the shared folder (`/home/jheem-shared/shield-container`):

1. Download the retained, tested pilot image and check it:

   ```bash
   cd /home/jheem-shared/shield-container
   gh release download shield-pilot-2026.10.01-r36815091235 \
     --repo ncsizemore/jheem-containers \
     --pattern jheem-shield-recorded.tar.gz --pattern IMAGE.txt --dir image
   (cd image && grep ' jheem-shield-recorded.tar.gz$' IMAGE.txt | sha256sum -c -)
   ```

   `IMAGE.txt` records the image ID, archive checksum, source revisions, and
   originating workflow run. For a newer candidate, export it from a successful
   `shield-spike` run and retain that exact image before the temporary Actions
   artifact expires. Do not replace a shared pilot installation while it has
   active runs; use a separate installation directory for the new image.

2. Prepare the pinned manager inputs and copy the script:

   ```bash
   python3 <jheem-containers>/workloads/shield/tests/prepare_inputs.py cache
   cp <jheem-containers>/workloads/shield/shield-run.sh .
   ```

3. Make the folder readable to the team and to containers (SELinux):

   ```bash
   chmod -R g+rX,o-rwx /home/jheem-shared/shield-container
   sudo chcon -R -t container_file_t /home/jheem-shared/shield-container/cache
   ```

4. Let containers reach the NAS: `sudo setsebool -P virt_use_samba on`

Per user: `sudo loginctl enable-linger <username>`, so their runs survive
logout. Users need to be in the `jheem` group to write to the NAS.

Each user's container image is stored in their own home directory (about 4 GB),
because Podman runs without root.
