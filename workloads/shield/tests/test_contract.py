from pathlib import Path
import os
import re
import subprocess

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parents[1]
WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "shield-spike.yml"


def test_canary_inspects_completed_simset_values():
    script = (ROOT / "tests" / "test_records_and_pipeline.sh").read_text()
    workflow = WORKFLOW.read_text()
    assert "inspect-recorded-outputs.R" in script
    assert script.index("inspect-recorded-outputs.R") < script.index("# Negative checks")
    assert 'numeric-$2.json' in script
    assert "test-output-checks.R" in workflow


def test_recorded_image_pins_base_and_source_defaults():
    dockerfile = (ROOT / "Dockerfile").read_text()
    assert re.search(r"BASE_IMAGE=.*@sha256:[0-9a-f]{64}", dockerfile)
    assert re.search(r"JHEEM_ANALYSES_REF=[0-9a-f]{40}", dockerfile)
    assert re.search(r"JHEEM2_REF=[0-9a-f]{40}", dockerfile)
    assert re.search(r"LOCATIONS_REF=[0-9a-f]{40}", dockerfile)
    assert "FROM runtime AS recorded" in dockerfile
    assert "FROM runtime AS development" in dockerfile
    assert "FROM ${BASE_IMAGE} AS source-preparer" in dockerfile
    # Team packages are installed before the SHIELD code is copied or its
    # revision declared, so a SHIELD-only change reuses the installed layers.
    install = dockerfile.index("R CMD INSTALL")
    assert install < dockerfile.index("ARG JHEEM_ANALYSES_REF=")
    assert install < dockerfile.index(
        "COPY --from=source-preparer /opt/jheem/jheem_analyses/ /opt/jheem/jheem_analyses/"
    )


def test_runtime_does_not_mutate_source_or_install_packages():
    dockerfile = (ROOT / "Dockerfile").read_text()
    entrypoint = (ROOT / "container-entrypoint.sh").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    runtime_text = entrypoint + preflight
    forbidden = ("git pull", "git fetch", "git reset", "git checkout", "install.packages")
    assert all(token not in runtime_text for token in forbidden)
    assert "chmod -R a+rX /root/.cache/R/renv" in dockerfile
    # Kept source references make every saved simulation carry package state.
    assert "--without-keep.source" in dockerfile
    assert "has functions with kept source references" in dockerfile


def test_recorded_profile_is_fail_closed():
    dockerfile = (ROOT / "Dockerfile").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    assert "SHIELD_RECORDED_RUN=true" in dockerfile
    assert "SHIELD_REQUIRE_IMMUTABLE_INPUTS=true" in dockerfile
    assert "shield.recorded.config()" in preflight
    assert "Recorded profile requires SHIELD_RECORDED_RUN=true" in preflight
    assert "fails SHA-256 verification" in preflight


def test_ci_build_is_pinned_validation_only():
    workflow_text = WORKFLOW.read_text()
    workflow = yaml.load(workflow_text, Loader=yaml.BaseLoader)
    dockerfile = (ROOT / "Dockerfile").read_text()

    assert workflow["permissions"] == {"contents": "read"}
    assert set(workflow["on"]) == {"push", "pull_request", "workflow_dispatch"}
    assert workflow["on"]["push"]["branches"] == ["main"]

    build = workflow["jobs"]["build-recorded"]
    assert build["if"] == "github.event_name != 'push'"
    assert build["needs"] == "contract"
    build_step = next(
        step for step in build["steps"]
        if step.get("uses") == "docker/build-push-action@v7"
    )
    build_inputs = build_step["with"]

    assert build_inputs["target"] == "recorded"
    assert build_inputs["platforms"] == "linux/amd64"
    assert build_inputs["load"] == "true"
    assert build_inputs["push"] == "false"
    assert build_inputs["tags"] == "jheem-shield:ci"
    assert "docker/login-action" not in workflow_text
    assert "packages: write" not in workflow_text
    assert "promot" not in workflow_text.lower().replace("promotion path", "")

    analyses_ref = re.search(r"JHEEM_ANALYSES_REF=([0-9a-f]{40})", dockerfile).group(1)
    jheem2_ref = re.search(r"JHEEM2_REF=([0-9a-f]{40})", dockerfile).group(1)
    locations_ref = re.search(r"LOCATIONS_REF=([0-9a-f]{40})", dockerfile).group(1)
    contexts = build_inputs["build-contexts"]
    # A manual run may name another analyses commit; the default is the
    # Dockerfile's, and the image records whichever was built.
    assert "jheem_analyses.git#${{ env.JHEEM_ANALYSES_REF }}" in contexts
    assert build["env"]["JHEEM_ANALYSES_REF"] == (
        "${{ inputs.jheem_analyses_ref || '" + analyses_ref + "' }}"
    )
    assert "JHEEM_ANALYSES_REF=${{ env.JHEEM_ANALYSES_REF }}" in build_inputs["build-args"]
    assert "^[0-9a-f]{40}$" in workflow_text
    assert f"jheem2.git#{jheem2_ref}" in contexts
    assert f"locations.git#{locations_ref}" in contexts

    assert "prepare_inputs.py" in workflow_text
    assert "--network none" in workflow_text
    assert "JHEEM_CENSUS_MANAGER_TAG" in workflow_text
    assert "JHEEM_SYPHILIS_MANAGER_TAG" in workflow_text
    assert "run_shield preflight" in workflow_text
    assert "test_checkpoint_resume.sh" in workflow_text
    assert "test_records_and_pipeline.sh" in workflow_text
    # Carry /app's pinned library into standalone tests in the source tree.
    assert "writeLines(paste(.libPaths()" in workflow_text
    assert workflow_text.index("export R_LIBS") < workflow_text.index(
        'cd "$JHEEM_ANALYSES_PATH"'
    )
    assert workflow_text.index("test_checkpoint_resume.sh") < workflow_text.index(
        "test_records_and_pipeline.sh"
    )
    assert "SHIELD_ENABLE_CONTAINER_SMOKE=true" in (
        ROOT / "tests" / "test_checkpoint_resume.sh"
    ).read_text()


def test_ci_input_fixture_uses_immutable_release_assets():
    preparer = (ROOT / "tests" / "prepare_inputs.py").read_text()
    assert "-latest" not in preparer
    assert "data-managers-v2026.08.26" in preparer
    assert "syphilis-manager-v2026.07.27" in preparer
    assert "syphilis-manager-v2026.05.05" in preparer
    assert len(re.findall(r'"sha256": "[0-9a-f]{64}"', preparer)) == 3
    assert "os.replace(temporary_path, artifact)" in preparer


def test_ci_profile_controls_preparer_and_all_canary_steps():
    workflow = yaml.load(WORKFLOW.read_text(), Loader=yaml.BaseLoader)
    profile = workflow["on"]["workflow_dispatch"]["inputs"]["input_profile"]
    assert profile["options"] == ["retained", "native-2026-10-01"]
    assert profile["default"] == "retained"
    build = workflow["jobs"]["build-recorded"]
    assert build["env"]["SHIELD_INPUT_PROFILE"] == "${{ inputs.input_profile || 'retained' }}"
    prepare = next(s for s in build["steps"] if s.get("name") == "prepare pinned test inputs")
    assert '--profile "$SHIELD_INPUT_PROFILE" --github-env "$GITHUB_ENV"' in prepare["run"]
    for step in build["steps"]:
        # Test stages must use the tags emitted by the selected preparer profile.
        assert "SYPHILIS_TAG" not in step.get("env", {})
        assert "CENSUS_TAG" not in step.get("env", {})
    for name in ("test_checkpoint_resume.sh", "test_records_and_pipeline.sh"):
        script = (ROOT / "tests" / name).read_text()
        assert '"SHIELD_RANDOM_SEED=${SHIELD_RANDOM_SEED:-20260916}"' in script


def test_entrypoint_records_every_attempt():
    entrypoint = (ROOT / "container-entrypoint.sh").read_text()
    # Attempts are recorded before any work and again when they end, so the
    # launcher runs as a child rather than replacing the shell.
    assert 'write_attempt started null ""' in entrypoint
    assert 'write_attempt "$stage_status" "$stage_exit"' in entrypoint
    assert "exec Rscript \"${JHEEM_ANALYSES_PATH}" not in entrypoint
    # A pipeline decides each stage from the recorded files, never by clearing state.
    assert '"$records/outputs.json"' in entrypoint
    assert '"$records/inputs.json"' in entrypoint
    assert "clear.calibration.cache" not in entrypoint


@pytest.mark.parametrize("case", ["saved_state", "receipt_only", "unrecorded_pipeline", "no_checkpoint"])
def test_wrapper_preserves_failed_state_and_gives_safe_recovery(tmp_path, case):
    """Exercise the real shell guards, without contacting Podman or a server."""
    shared = tmp_path / "shared"
    state = tmp_path / "state"
    binary = tmp_path / "bin"
    binary.mkdir()
    (shared / "image").mkdir(parents=True)
    (shared / "cache" / "data-managers").mkdir(parents=True)
    (shared / "image" / "IMAGE.txt").write_text("image_id=sha256:abc\n")
    saved = state / "mcmc_runs" / "shield" / "test.stage0" / "C.12580"
    records = state / "run_records" / "shield" / "C.12580" / "test.stage0"
    if case != "receipt_only":
        saved.mkdir(parents=True)
        (saved / "keep.txt").write_text("unfinished calibration\n")
    if case in ("receipt_only", "no_checkpoint"):
        records.mkdir(parents=True)
        (records / "inputs.json").write_text('{"preserve": true}\n')

    # Any destructive/container-start call is an unexpected test failure.
    commands = {
        "podman": '''case "$1 $2" in
  "image inspect") echo abc ;;
  "ps -a") exit 0 ;;
  *) echo "unexpected podman operation: $*" >> "$FAKE_PODMAN_LOG"; exit 97 ;;
esac''',
        "loginctl": "echo yes",
        "stat": "echo ext2",
        "tac": "cat",
    }
    for name, body in commands.items():
        path = binary / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    log = tmp_path / "podman.log"
    env = dict(os.environ, SHIELD_HOME=str(shared), SHIELD_STATE_ROOT=str(state),
               FAKE_PODMAN_LOG=str(log), PATH=str(binary) + os.pathsep + os.environ["PATH"])
    before = {p.relative_to(state): p.read_bytes() for p in state.rglob("*") if p.is_file()}
    action = {"unrecorded_pipeline": "pipeline", "no_checkpoint": "resume"}.get(case, "start")
    result = subprocess.run(
        ["bash", str(ROOT / "shield-run.sh"), action, "C.12580", "test.stage0"],
        env=env, capture_output=True, text=True,
    )
    assert result.returncode == 1, result.stderr
    assert "SHIELD_STATE_ROOT" in result.stderr
    assert "preserve" in result.stderr.lower()
    assert "remove that folder" not in result.stderr.lower()
    assert not log.exists(), log.read_text() if log.exists() else ""
    after = {p.relative_to(state): p.read_bytes() for p in state.rglob("*") if p.is_file()}
    assert after == before
