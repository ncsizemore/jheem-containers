import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


SHIELD = Path(__file__).resolve().parents[1]
ENTRYPOINT = SHIELD / "container-entrypoint.sh"

# Stands in for Rscript. Preflight passes; the launcher acts out its phase:
# setup writes the receipt and chain count, each chain logs, assembly writes
# outputs. FAKE_FAIL_CHAIN makes one chain fail; FAKE_CHAINS sets the count.
FAKE_RSCRIPT = r'''#!/bin/sh
case "$1" in */preflight.R) exit 0 ;; esac
records="$JHEEM_ROOT_DIR/run_records/shield/$2/$3"
echo "$SHIELD_RECORDED_PHASE ${SHIELD_RECORDED_CHAIN:-} $SHIELD_RUN_MODE" >> "$FAKE_TRACE"
case "$SHIELD_RECORDED_PHASE" in
  setup)
    echo '{}' > "$records/inputs.json"
    echo "${FAKE_CHAINS:-4}" > "$records/chains.txt" ;;
  run)
    echo "sampling chain $SHIELD_RECORDED_CHAIN"
    [ "$SHIELD_RECORDED_CHAIN" != "${FAKE_FAIL_CHAIN:-none}" ] || exit 9 ;;
  assemble|all)
    echo '{}' > "$records/outputs.json" ;;
esac
'''


@pytest.fixture
def env(tmp_path):
    binary = tmp_path / "bin"
    binary.mkdir()
    (binary / "Rscript").write_text(FAKE_RSCRIPT)
    if not shutil.which("sha256sum"):
        (binary / "sha256sum").write_text('#!/bin/sh\nexec shasum -a 256 "$@"\n')
    for tool in binary.iterdir():
        tool.chmod(0o755)
    analyses = tmp_path / "jheem_analyses"
    runtime = analyses / "applications/SHIELD/R/shield_recorded_runtime.R"
    runtime.parent.mkdir(parents=True)
    runtime.write_text("shield.recorded.phase <- function(getenv = Sys.getenv) NULL\n")
    (tmp_path / "state").mkdir()
    return dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                JHEEM_ROOT_DIR=str(tmp_path / "state"), JHEEM_ANALYSES_PATH=str(analyses),
                SHIELD_RUNTIME_HOME=str(tmp_path / "home"), FAKE_TRACE=str(tmp_path / "trace"))


# The image's /bin/sh is dash; use it when available so its stricter POSIX
# behavior (background jobs, wait) is what the tests exercise.
SHELL = shutil.which("dash") or "sh"


def run(env, *args, **extra):
    return subprocess.run([SHELL, str(ENTRYPOINT), *args], env=dict(env, **extra),
                          capture_output=True, text=True)


def trace(env):
    return Path(env["FAKE_TRACE"]).read_text().split("\n")[:-1]


def attempts(env, calibration="stage3"):
    directory = Path(env["JHEEM_ROOT_DIR"]) / "run_records/shield/C.12580" / calibration / "attempts"
    return [json.loads(path.read_text()) for path in sorted(directory.glob("*.json"))]


def test_fresh_stage_runs_setup_parallel_chains_then_assembly(env):
    result = run(env, "calibrate", "C.12580", "stage3", SHIELD_RUN_MODE="fresh")
    assert result.returncode == 0, result.stderr
    steps = trace(env)
    assert steps[0] == "setup  fresh"
    assert sorted(steps[1:5]) == ["run 1 resume", "run 2 resume", "run 3 resume", "run 4 resume"]
    assert steps[5] == "assemble  resume"
    records = attempts(env)
    assert sorted((a["phase"], a["chain"], a["status"]) for a in records) == [
        ("assemble", None, "succeeded"), ("run", 1, "succeeded"), ("run", 2, "succeeded"),
        ("run", 3, "succeeded"), ("run", 4, "succeeded"), ("setup", None, "succeeded")]
    assert all(len(a["runner"]["entrypoint_sha256"]) == 64 for a in records)
    logs = Path(env["JHEEM_ROOT_DIR"]) / "run_records/shield/C.12580/stage3/logs"
    assert sorted(p.read_text() for p in logs.iterdir()) == [
        "sampling chain %d\n" % chain for chain in (1, 2, 3, 4)]
    assert "chain 3 finished (exit 0)" in result.stdout


def test_failed_chain_skips_assembly_and_a_rerun_continues(env):
    result = run(env, "pipeline", "C.12580", "stage3", FAKE_FAIL_CHAIN="2")
    assert result.returncode != 0
    assert "has a failed chain; not assembling" in result.stderr
    assert not any(step.startswith("assemble") for step in trace(env))
    assert not (Path(env["JHEEM_ROOT_DIR"]) / "run_records/shield/C.12580/stage3/outputs.json").exists()
    Path(env["FAKE_TRACE"]).unlink()
    result = run(env, "pipeline", "C.12580", "stage3")
    assert result.returncode == 0, result.stderr
    # Setup isn't repeated; every chain continues, then the stage assembles.
    assert sorted(trace(env)[:4]) == ["run 1 resume", "run 2 resume", "run 3 resume", "run 4 resume"]
    assert trace(env)[4:] == ["assemble  resume"]
    failed = [a for a in attempts(env) if a["status"] == "failed"]
    assert [(a["phase"], a["chain"], a["exit_code"]) for a in failed] == [("run", 2, 9)]


def test_parallel_chains_are_limited_in_batches(env):
    result = run(env, "calibrate", "C.12580", "stage3", SHIELD_RUN_MODE="fresh",
                 SHIELD_MAX_PARALLEL_CHAINS="1")
    assert result.returncode == 0, result.stderr
    assert trace(env)[1:5] == ["run 1 resume", "run 2 resume", "run 3 resume", "run 4 resume"]


def test_single_chain_stage_logs_to_the_container(env):
    result = run(env, "calibrate", "C.12580", "stage0", SHIELD_RUN_MODE="fresh", FAKE_CHAINS="1")
    assert result.returncode == 0, result.stderr
    assert trace(env) == ["setup  fresh", "run 1 resume", "assemble  resume"]
    assert "sampling chain 1" in result.stdout


def test_resume_without_a_recorded_chain_count_is_refused(env):
    records = Path(env["JHEEM_ROOT_DIR"]) / "run_records/shield/C.12580/stage3"
    records.mkdir(parents=True)
    (records / "inputs.json").write_text("{}")
    result = run(env, "calibrate", "C.12580", "stage3", SHIELD_RUN_MODE="resume")
    assert result.returncode == 64
    assert "no recorded chain count" in result.stderr


def test_analysis_code_without_phases_keeps_the_single_process_launcher(env):
    runtime = Path(env["JHEEM_ANALYSES_PATH"]) / "applications/SHIELD/R/shield_recorded_runtime.R"
    runtime.write_text("# recorded runtime from before phased runs\n")
    result = run(env, "calibrate", "C.12580", "stage0", SHIELD_RUN_MODE="fresh")
    assert result.returncode == 0, result.stderr
    assert trace(env) == ["all  fresh"]
    assert [(a["run_mode"], a["phase"]) for a in attempts(env, "stage0")] == [("fresh", "all")]
