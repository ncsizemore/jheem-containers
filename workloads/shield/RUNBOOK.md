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
has saved results; it tells you to use `resume`, or which folder to remove to
start over. Don't start the same calibration for the same location twice at the
same time, including from another account.

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
- `run_records/shield/<location>/<calibration>/inputs.json`: exactly which code
  and data versions the run used

These are test locations while the container is being tried out; they don't
touch the team's usual `mcmc_runs`.

## If something goes wrong

- **`lingering is off`** or **`containers can't reach the NAS`**: the
  administrator setup isn't finished; send the message to the administrator.
- **`is already running`**: that calibration is still going; check `shield-run
  status`.
- **`status` shows `exited` with a number other than 0:** run `shield-run logs
  <location> <calibration>` and send the last lines to whoever supports the
  container.
- **A `resume` fails straight away:** the run's saved inputs don't match, or
  there is no checkpoint yet. Send the `logs` output.

---

## Administrator setup (once per server, and once per user)

Per server, in the shared folder (`/home/jheem-shared/shield-container`):

1. Download the tested image from a `shield-spike` workflow run with image export
   on, and check it:

   ```bash
   cd /home/jheem-shared/shield-container
   gh run download <run-id> --repo ncsizemore/jheem-containers --name shield-recorded-image --dir image
   (cd image && grep ' jheem-shield-recorded.tar.gz$' IMAGE.txt | sha256sum -c -)
   ```

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
