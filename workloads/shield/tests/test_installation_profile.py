import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

import pytest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installation", ROOT / "installation_profile.py")
installation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installation)
IMAGE = "sha256:" + "a" * 64


@pytest.fixture
def home(tmp_path):
    home = tmp_path / "candidate"
    image = home / "image"
    image.mkdir(parents=True)
    archive = image / "jheem-shield-recorded.tar.gz"
    manifest = json.dumps([{"RepoTags": ["jheem-shield:pilot-r12345"]}]).encode()
    with tarfile.open(archive, "w:gz") as saved:
        info = tarfile.TarInfo("manifest.json")
        info.size = len(manifest)
        saved.addfile(info, io.BytesIO(manifest))
    values = {"image_id": IMAGE, "image_tag": "docker.io/library/jheem-shield:pilot-r12345",
              "workflow_run": "12345", "containers_commit": "b" * 40,
              "jheem_analyses_ref": "c" * 40, "jheem2_ref": "d" * 40,
              "input_profile": "september-2026", "census_tag": "data-managers-v2026.08.26",
              "syphilis_tag": "syphilis-manager-v2026.09.09", "random_seed": "0"}
    metadata = "".join(f"{key}={value}\n" for key, value in values.items())
    (image / "IMAGE.txt").write_text(metadata + installation.digest(archive) + "  jheem-shield-recorded.tar.gz\n")
    for manager, key in zip(installation.MANAGERS, ("census_tag", "syphilis_tag")):
        directory = home / "cache/data-managers" / manager / values[key]
        directory.mkdir(parents=True)
        content = ("synthetic " + manager).encode()
        (directory / manager).write_bytes(content)
        (directory / "resolution.json").write_text(json.dumps({
            "repository": "tfojo1/jheem_analyses", "manager": manager,
            "resolved_tag": values[key], "sha256": hashlib.sha256(content).hexdigest(),
        }))
    return home


def test_verified_profile_binds_runtime_inputs_and_separate_output_namespace(home):
    profile = installation.prepare(home)
    assert profile == installation.read_profile(home)
    assert profile["state_namespace"] == "shield-container-r12345"
    assert profile["image"]["image_id"] == IMAGE
    assert profile["inputs"][1]["tag"] == "syphilis-manager-v2026.09.09"
    installation.verify_inputs(home, profile)
    with pytest.raises(ValueError, match="preserve"):
        installation.prepare(home)


@pytest.mark.parametrize("damage", ["archive", "archive-tag", "manager", "resolution", "tag", "duplicate", "symlink"])
def test_invalid_payload_cannot_create_an_installation_profile(home, damage):
    manager = home / "cache/data-managers/syphilis.manager.rdata/syphilis-manager-v2026.09.09"
    if damage == "archive":
        (home / "image/jheem-shield-recorded.tar.gz").write_bytes(b"wrong image")
    elif damage == "archive-tag":
        archive = home / "image/jheem-shield-recorded.tar.gz"
        old_checksum = installation.digest(archive)
        manifest = json.dumps([{"RepoTags": ["jheem-shield:ci"]}]).encode()
        with tarfile.open(archive, "w:gz") as saved:
            info = tarfile.TarInfo("manifest.json")
            info.size = len(manifest)
            saved.addfile(info, io.BytesIO(manifest))
        metadata = home / "image/IMAGE.txt"
        metadata.write_text(metadata.read_text().replace(old_checksum, installation.digest(archive)))
    elif damage == "manager":
        (manager / "syphilis.manager.rdata").write_bytes(b"wrong manager")
    elif damage == "resolution":
        (manager / "resolution.json").write_text("{}")
    elif damage == "symlink":
        artifact = manager / "syphilis.manager.rdata"
        copy = artifact.with_suffix(".original")
        artifact.rename(copy)
        artifact.symlink_to(copy)
    else:
        metadata = home / "image/IMAGE.txt"
        value = metadata.read_text()
        metadata.write_text(value.replace("pilot-r12345", "ci") if damage == "tag"
                            else value + "image_id=" + IMAGE + "\n")
    with pytest.raises(ValueError):
        installation.prepare(home)
    assert not (home / "installation.json").exists()


@pytest.mark.parametrize("census_tag,valid", [("census-manager-v2026.10.08", True),
                                               ("census-manager-latest", False),
                                               ("syphilis-manager-v2026.09.09", False),
                                               ("data-managers-latest", False)])
def test_census_may_come_from_a_census_only_release(home, census_tag, valid):
    old = "data-managers-v2026.08.26"
    metadata = home / "image/IMAGE.txt"
    metadata.write_text(metadata.read_text().replace(old, census_tag))
    cache = home / "cache/data-managers/census.manager.rdata"
    (cache / old).rename(cache / census_tag)
    resolution = json.loads((cache / census_tag / "resolution.json").read_text())
    resolution["resolved_tag"] = census_tag
    (cache / census_tag / "resolution.json").write_text(json.dumps(resolution))
    if valid:
        assert installation.prepare(home)["inputs"][0]["tag"] == census_tag
    else:
        with pytest.raises(ValueError, match="immutable manager release"):
            installation.prepare(home)
        assert not (home / "installation.json").exists()


@pytest.mark.parametrize("namespace", ["../old", "shield-container/old", "", "/mnt/other"])
def test_namespace_cannot_escape_the_per_user_pilot_root(home, namespace):
    if namespace == "":
        profile = installation.prepare(home)
        profile["state_namespace"] = namespace
        (home / "installation.json").write_text(json.dumps(profile))
        operation = lambda: installation.read_profile(home)
    else:
        operation = lambda: installation.prepare(home, namespace)
    with pytest.raises(ValueError, match="namespace"):
        operation()


def test_changed_installed_selection_is_rejected(home):
    installation.prepare(home)
    metadata = home / "image/IMAGE.txt"
    metadata.write_text(metadata.read_text().replace("2026.09.09", "2026.07.27"))
    with pytest.raises(ValueError, match="differs"):
        installation.read_profile(home)


def install_wrapper(home, tmp_path):
    for name in ("shield-run.sh", "installation_profile.py"):
        shutil.copyfile(ROOT / name, home / name)
    binary = tmp_path / "bin"
    binary.mkdir()
    log = tmp_path / "podman.log"
    for name, body in {"podman": 'echo "$*" >> "$FAKE_LOG"; case "$1 $2" in "image inspect") echo ' + IMAGE + ';; "ps -a") ;; *) exit 97;; esac',
                       "loginctl": "echo yes", "stat": "echo ext2"}.items():
        path = binary / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    env = {key: value for key, value in os.environ.items()
           if key not in ("SHIELD_HOME", "SHIELD_IMAGE", "CENSUS_TAG", "SYPHILIS_TAG", "SHIELD_RANDOM_SEED")}
    env.update(FAKE_LOG=str(log), SHIELD_STATE_ROOT=str(tmp_path / "runs"),
               PATH=str(binary) + os.pathsep + env["PATH"])
    return env, log


def test_installed_wrapper_selects_its_own_profile_without_operator_overrides(home, tmp_path):
    installation.prepare(home)
    env, log = install_wrapper(home, tmp_path)
    result = subprocess.run(["bash", str(home / "shield-run.sh"), "setup"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "syphilis-manager-v2026.09.09; seed: 0" in result.stdout
    assert IMAGE in log.read_text()
    assert "ci" not in log.read_text()
    assert "run " not in log.read_text()


@pytest.mark.parametrize("selection,value", [("SYPHILIS_TAG", "syphilis-manager-v2026.07.27"),
                          ("CENSUS_TAG", "latest"), ("SHIELD_IMAGE", "jheem-shield:ci")])
def test_conflicting_environment_selection_stops_before_any_container_operation(home, tmp_path, selection, value):
    installation.prepare(home)
    env, log = install_wrapper(home, tmp_path)
    env[selection] = value
    result = subprocess.run(["bash", str(home / "shield-run.sh"), "setup"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 1
    assert selection + " differs" in result.stderr
    assert not log.exists()


def test_new_export_without_installation_profile_never_defaults_to_july(home, tmp_path):
    env, log = install_wrapper(home, tmp_path)
    result = subprocess.run(["bash", str(home / "shield-run.sh"), "setup"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 1
    assert "prepared installation.json" in result.stderr
    assert not log.exists()


def test_workflow_exports_only_a_unique_alias_of_the_tested_image():
    workflow = (ROOT.parents[1] / ".github/workflows/shield-spike.yml").read_text()
    assert 'pilot_tag="jheem-shield:pilot-r${GITHUB_RUN_ID}"' in workflow
    assert 'docker tag jheem-shield:ci "$pilot_tag"' in workflow
    assert 'docker save "$pilot_tag"' in workflow
    assert 'echo "image_tag=docker.io/library/$pilot_tag"' in workflow


def test_profile_flows_through_real_source_selection_and_detached_wrapper_launch(home, tmp_path):
    installation.prepare(home)
    env, log = install_wrapper(home, tmp_path)
    shutil.copyfile(ROOT / "source_snapshot.py", home / "source_snapshot.py")
    source = tmp_path / "source"
    source.mkdir()
    for name in ("applications/SHIELD/R/shield_recorded_runtime.R",
                 "applications/SHIELD/shield_calib_setup_and_run.R",
                 "applications/SHIELD/check_recorded_completion.R"):
        path = source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# synthetic source-selection fixture\n")
    for args in (("init", "-q"), ("config", "user.email", "test@example.invalid"),
                 ("config", "user.name", "Fixture"), ("add", "."), ("commit", "-qm", "fixture")):
        subprocess.run(["git", "-C", str(source), *args], check=True, capture_output=True)
    env["SHIELD_SOURCE_DIR"] = str(source)
    # This fixture has no jheem2 checkout; engine capture is covered in test_engine_build.py.
    env["SHIELD_ENGINE"] = "image"
    binary = tmp_path / "bin/podman"
    binary.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as output:
    output.write(json.dumps(args) + "\\n")
if args[:2] == ["image", "inspect"]:
    print("sha256:" + "a" * 64)
elif args[0] == "run":
    print("fake-container")
elif args[0] != "ps":
    sys.exit(97)
''')
    for name, body in (("tac", "cat"),):
        path = tmp_path / "bin" / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    result = subprocess.run(["bash", str(home / "shield-run.sh"), "start", "C.12580", "test.stage0"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    runs = [args for args in calls if args[0] == "run"]
    assert len(runs) == 2 and "--rm" in runs[0] and "-d" in runs[1]
    for args in runs:
        assert IMAGE in args
        assert "JHEEM_SYPHILIS_MANAGER_TAG=syphilis-manager-v2026.09.09" in args
        assert "SHIELD_RANDOM_SEED=0" in args
        assert any("dst=/opt/run-source/jheem_analyses,readonly" in value for value in args)
    assert all("jheem-shield:ci" not in arg for call in calls for arg in call)
