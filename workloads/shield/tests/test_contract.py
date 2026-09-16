from pathlib import Path
import re

import yaml


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ROOT.parents[1]
WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "shield-spike.yml"


def test_recorded_image_pins_base_and_source_defaults():
    dockerfile = (ROOT / "Dockerfile").read_text()
    assert re.search(r"BASE_IMAGE=.*@sha256:[0-9a-f]{64}", dockerfile)
    assert re.search(r"JHEEM_ANALYSES_REF=[0-9a-f]{40}", dockerfile)
    assert re.search(r"JHEEM2_REF=[0-9a-f]{40}", dockerfile)
    assert re.search(r"LOCATIONS_REF=[0-9a-f]{40}", dockerfile)
    assert "FROM runtime AS recorded" in dockerfile
    assert "FROM runtime AS development" in dockerfile
    assert "FROM ${BASE_IMAGE} AS source-preparer" in dockerfile
    assert "COPY --from=source-preparer /opt/jheem/ /opt/jheem/" in dockerfile


def test_runtime_does_not_mutate_source_or_install_packages():
    dockerfile = (ROOT / "Dockerfile").read_text()
    entrypoint = (ROOT / "container-entrypoint.sh").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    runtime_text = entrypoint + preflight
    forbidden = ("git pull", "git fetch", "git reset", "git checkout", "install.packages")
    assert all(token not in runtime_text for token in forbidden)
    assert "chmod -R a+rX /root/.cache/R/renv" in dockerfile


def test_recorded_profile_is_fail_closed():
    dockerfile = (ROOT / "Dockerfile").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    assert "SHIELD_INPUT_OFFLINE=true" in dockerfile
    assert "SHIELD_REQUIRE_IMMUTABLE_INPUTS=true" in dockerfile
    assert "SHIELD_ALLOW_INCOMPLETE=false" in dockerfile
    assert "Recorded profile does not permit incomplete assembly" in preflight
    assert "full JHEEM_ANALYSES_REF and JHEEM2_REF" in preflight


def test_ci_build_is_pinned_validation_only():
    workflow_text = WORKFLOW.read_text()
    workflow = yaml.load(workflow_text, Loader=yaml.BaseLoader)
    dockerfile = (ROOT / "Dockerfile").read_text()

    assert workflow["permissions"] == {"contents": "read"}
    assert set(workflow["on"]) == {"pull_request", "workflow_dispatch"}

    build = workflow["jobs"]["build-recorded"]
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
    assert f"jheem_analyses.git#{analyses_ref}" in contexts
    assert f"jheem2.git#{jheem2_ref}" in contexts
    assert f"locations.git#{locations_ref}" in contexts

    assert "prepare_inputs.py" in workflow_text
    assert "--network none" in workflow_text
    assert "JHEEM_CENSUS_MANAGER_TAG" in workflow_text
    assert "JHEEM_SYPHILIS_MANAGER_TAG" in workflow_text
    assert "run_shield preflight" in workflow_text
    assert "run_shield engine-test" in workflow_text
    assert "test_checkpoint_resume.sh" in workflow_text
    assert "SHIELD_ENABLE_CONTAINER_SMOKE=true" in (
        ROOT / "tests" / "test_checkpoint_resume.sh"
    ).read_text()


def test_ci_input_fixture_uses_immutable_release_assets():
    preparer = (ROOT / "tests" / "prepare_inputs.py").read_text()
    assert "-latest" not in preparer
    assert "data-managers-v2026.08.26" in preparer
    assert "syphilis-manager-v2026.03.26" in preparer
    assert len(re.findall(r'"sha256": "[0-9a-f]{64}"', preparer)) == 2
    assert "os.replace(temporary_path, artifact)" in preparer
