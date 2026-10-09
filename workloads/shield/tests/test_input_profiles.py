import hashlib
import importlib.util
import io
import json
from pathlib import Path

import pytest


spec = importlib.util.spec_from_file_location(
    "shield_prepare_inputs", Path(__file__).with_name("prepare_inputs.py")
)
preparer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preparer)


def test_comparison_profile_preserves_retained_default():
    assert preparer.PROFILES["retained"] == preparer.INPUTS
    retained, comparison = preparer.INPUTS, preparer.PROFILES["native-2026-10-01"]
    assert retained[0] == comparison[0]
    assert retained[1]["tag"] == "syphilis-manager-v2026.07.27"
    assert comparison[1]["tag"] == "syphilis-manager-v2026.05.05"
    assert comparison[1]["sha256"] == "e8acbeb758ae4af4e149a62ef78c862a114a2d55f43a0c4695f49d9a8a9fa0e6"
    september = preparer.PROFILES["september-2026"]
    assert september[0] == retained[0]
    assert september[1]["tag"] == "syphilis-manager-v2026.09.09"
    assert september[1]["sha256"] == "c3e3c983d6b4e9c961f735f9c59d45483bd63cfa715cf75c1fae874da2d129e6"
    october = preparer.PROFILES["october-2026"]
    assert october[1] == september[1]
    assert october[0]["manager"] == "census.manager.rdata"
    assert october[0]["tag"] == "census-manager-v2026.10.08"
    assert october[0]["sha256"] == "fc45487d38f87c8692ab0bc615d8f4b049d8da363956d7bf02d733c9aa9dee64"


@pytest.mark.parametrize("profile,seed", [("retained", "20260916"), ("native-2026-10-01", "0"),
                                          ("september-2026", "0"), ("october-2026", "0")])
def test_cli_exports_only_selected_verified_inputs(tmp_path, monkeypatch, profile, seed):
    materialized = []
    monkeypatch.setattr(preparer, "materialize", lambda cache, entry: materialized.append(entry))
    env = tmp_path / "environment"
    monkeypatch.setattr(preparer.sys, "argv", ["prepare_inputs.py", str(tmp_path / "cache"),
                        "--profile", profile, "--github-env", str(env)])
    preparer.main()
    assert tuple(materialized) == preparer.PROFILES[profile]
    assert env.read_text().splitlines() == [
        "CENSUS_TAG=" + materialized[0]["tag"],
        "SYPHILIS_TAG=" + materialized[1]["tag"], "SHIELD_RANDOM_SEED=" + seed,
    ]


@pytest.mark.parametrize("corrupt", [False, True])
def test_profile_artifact_still_requires_digest(tmp_path, monkeypatch, corrupt):
    content = b"synthetic manager artifact"
    entry = dict(preparer.NATIVE_OCTOBER_INPUTS[1], sha256=hashlib.sha256(content).hexdigest())
    monkeypatch.setattr(preparer, "urlopen", lambda *args, **kwargs: io.BytesIO(
        b"different artifact" if corrupt else content
    ))
    artifact = tmp_path / "data-managers" / entry["manager"] / entry["tag"] / entry["manager"]
    if corrupt:
        with pytest.raises(RuntimeError, match="SHA-256 mismatch"):
            preparer.materialize(tmp_path, entry)
        assert not artifact.exists()
        assert not artifact.with_name("resolution.json").exists()
    else:
        preparer.materialize(tmp_path, entry)
        assert artifact.read_bytes() == content
        assert json.loads(artifact.with_name("resolution.json").read_text())["resolved_tag"] == entry["tag"]
