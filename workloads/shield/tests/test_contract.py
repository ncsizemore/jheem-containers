from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def test_recorded_image_pins_base_and_source_defaults():
    dockerfile = (ROOT / "Dockerfile").read_text()
    assert re.search(r"BASE_IMAGE=.*@sha256:[0-9a-f]{64}", dockerfile)
    assert re.search(r"JHEEM_ANALYSES_REF=[0-9a-f]{40}", dockerfile)
    assert re.search(r"JHEEM2_REF=[0-9a-f]{40}", dockerfile)
    assert "FROM runtime AS recorded" in dockerfile
    assert "FROM runtime AS development" in dockerfile
    assert "FROM ${BASE_IMAGE} AS source-preparer" in dockerfile
    assert "COPY --from=source-preparer /opt/jheem/ /opt/jheem/" in dockerfile


def test_runtime_does_not_mutate_source_or_install_packages():
    entrypoint = (ROOT / "container-entrypoint.sh").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    runtime_text = entrypoint + preflight
    forbidden = ("git pull", "git fetch", "git reset", "git checkout", "install.packages")
    assert all(token not in runtime_text for token in forbidden)


def test_recorded_profile_is_fail_closed():
    dockerfile = (ROOT / "Dockerfile").read_text()
    preflight = (ROOT / "preflight.R").read_text()
    assert "SHIELD_INPUT_OFFLINE=true" in dockerfile
    assert "SHIELD_REQUIRE_IMMUTABLE_INPUTS=true" in dockerfile
    assert "SHIELD_ALLOW_INCOMPLETE=false" in dockerfile
    assert "Recorded profile does not permit incomplete assembly" in preflight
    assert "full JHEEM_ANALYSES_REF and JHEEM2_REF" in preflight
