import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest


SHIELD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHIELD))
spec = importlib.util.spec_from_file_location("engine_build", SHIELD / "engine_build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
import source_snapshot as snap  # noqa: E402

IMAGE = "sha256:" + "a" * 64
OTHER_IMAGE = "sha256:" + "b" * 64

# Stands in for podman: a build run writes a minimal installed package into the
# mounted build library; image inspection reports the expected image.
FAKE_PODMAN = '''import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args[:2] == ["image", "inspect"]:
    print("a" * 64)
elif args[0] == "run" and "/opt/shield/build_engine.sh" in args:
    if os.environ.get("FAKE_BUILD_FAIL") == "true":
        sys.exit(23)
    target = next(a.split("src=")[1].split(",")[0] for a in args
                  if a.startswith("type=bind") and "dst=/opt/run-engine/build" in a)
    package = os.path.join(target, "jheem2")
    os.makedirs(os.path.join(package, "R"))
    open(os.path.join(package, "DESCRIPTION"), "w").write("Package: jheem2\\n")
    open(os.path.join(package, "R", "jheem2"), "w").write("compiled\\n")
elif args[0] == "run":
    if "--rm" in args and os.environ.get("FAKE_COMPATIBLE") == "false":
        sys.exit(37)
    print("fake-container")
elif args[0] != "ps":
    sys.exit(97)
'''


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args]).decode().strip()


def make_repo(path, files):
    path.mkdir()
    git(path, "init", "-q")
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "Engine test")
    for name, text in files.items():
        (path / name).parent.mkdir(parents=True, exist_ok=True)
        (path / name).write_text(text)
    git(path, "add", ".")
    git(path, "commit", "-qm", "initial")
    return path


@pytest.fixture
def checkouts(tmp_path):
    analyses = make_repo(tmp_path / "jheem_analyses",
                         {**{name: "# fixture\n" for name in snap.REQUIRED}, "model.R": "x <- 1\n"})
    engine = make_repo(tmp_path / "jheem2", {"DESCRIPTION": "Package: jheem2\nVersion: 1\n",
                                             "NAMESPACE": "export(run)\n", "R/run.R": "run <- 1\n"})
    return analyses, engine


@pytest.fixture
def fake_tools(tmp_path, monkeypatch):
    binary = tmp_path / "bin"
    binary.mkdir()
    (binary / "podman").write_text("#!" + sys.executable + "\n" + FAKE_PODMAN)
    for name, body in (("loginctl", "echo yes"), ("stat", "echo ext2"), ("tac", "cat")):
        (binary / name).write_text("#!/bin/sh\n" + body + "\n")
    for tool in binary.iterdir():
        tool.chmod(0o755)
    log = tmp_path / "podman.jsonl"
    monkeypatch.setenv("FAKE_LOG", str(log))
    monkeypatch.setenv("PATH", str(binary) + os.pathsep + os.environ["PATH"])
    return log


def runs(log, kind=None):
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    calls = [args for args in calls if args[0] == "run"]
    if kind == "build":
        return [args for args in calls if "/opt/shield/build_engine.sh" in args]
    if kind == "model":
        return [args for args in calls if "/opt/shield/build_engine.sh" not in args]
    return calls


def captured(tmp_path, checkouts, code="stage0"):
    analyses, _ = checkouts
    return snap.select(tmp_path / "runs", analyses, (code,), IMAGE, "data-managers-v2026.08.26",
                       "syphilis-manager-v2026.07.27", "0")


def test_builds_once_per_engine_and_image(tmp_path, checkouts, fake_tools):
    chosen = captured(tmp_path, checkouts)
    library = build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD)
    marker = (library / "jheem2" / build.MARKER).read_text()
    assert "engine_commit: " + chosen["engine_commit"] in marker
    assert build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD) == library
    assert len(runs(fake_tools, "build")) == 1
    other = build.ensure(tmp_path / "runs", chosen["engine"], OTHER_IMAGE, SHIELD)
    assert other != library
    assert len(runs(fake_tools, "build")) == 2
    args = runs(fake_tools, "build")[0]
    assert "--network" in args and "none" in args
    assert any(a.startswith("type=bind,src=" + chosen["engine_path"] + ",dst=/opt/run-engine/jheem2,readonly")
               for a in args)


def test_damaged_build_is_refused_not_rebuilt(tmp_path, checkouts, fake_tools):
    chosen = captured(tmp_path, checkouts)
    library = build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD)
    (library / "jheem2/R/jheem2").write_text("changed\n")
    with pytest.raises(ValueError, match="engine build files changed"):
        build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD)
    assert len(runs(fake_tools, "build")) == 1


def test_failed_build_leaves_nothing_to_reuse(tmp_path, checkouts, fake_tools, monkeypatch):
    chosen = captured(tmp_path, checkouts)
    monkeypatch.setenv("FAKE_BUILD_FAIL", "true")
    with pytest.raises(subprocess.CalledProcessError):
        build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD)
    builds = tmp_path / "runs/run_sources/engine-builds"
    assert list(builds.iterdir()) == []
    monkeypatch.setenv("FAKE_BUILD_FAIL", "false")
    assert build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD).is_dir()


def test_waits_for_a_concurrent_build_then_gives_up(tmp_path, checkouts, fake_tools):
    chosen = captured(tmp_path, checkouts)
    builds = tmp_path / "runs/run_sources/engine-builds"
    builds.mkdir(parents=True)
    (builds / (".lock-" + build.build_key(chosen["engine"], IMAGE))).mkdir()
    with pytest.raises(ValueError, match="building this engine for too long"):
        build.ensure(tmp_path / "runs", chosen["engine"], IMAGE, SHIELD,
                     wait_seconds=0.05, poll_seconds=0.01)
    assert runs(fake_tools, "build") == []


def test_wrapper_builds_and_mounts_the_captured_engine(tmp_path, checkouts, fake_tools):
    analyses, engine = checkouts
    shared = tmp_path / "shared"
    (shared / "image").mkdir(parents=True)
    (shared / "cache/data-managers").mkdir(parents=True)
    (shared / "image/IMAGE.txt").write_text("image_id=" + IMAGE + "\n")
    state = tmp_path / "runs"
    env = dict(os.environ, SHIELD_HOME=str(shared), SHIELD_STATE_ROOT=str(state),
               SHIELD_SOURCE_DIR=str(analyses), FAKE_COMPATIBLE="true")
    for location in ("C.12580", "C.35620"):
        result = subprocess.run(["bash", str(SHIELD / "shield-run.sh"), "start", location, "stage0"],
                                env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
    engine_commit = git(engine, "rev-parse", "HEAD")
    assert "Using saved jheem2 " + engine_commit[:8] in result.stdout
    # One build serves both locations; each launch checks, then starts the run.
    assert len(runs(fake_tools, "build")) == 1
    model = runs(fake_tools, "model")
    assert len(model) == 4
    for args in model:
        assert "JHEEM2_REF=" + engine_commit in args
        assert "R_PROFILE_USER=/opt/shield/engine-profile.R" in args
        assert "SHIELD_ENGINE_LIBRARY=/opt/run-engine/library" in args
        assert any("dst=/opt/run-engine/jheem2,readonly" in a for a in args)
        assert any("dst=/opt/run-engine/library,readonly" in a for a in args)
        assert str(engine) + "," not in " ".join(args)


def test_wrapper_can_explicitly_use_the_image_engine(tmp_path, checkouts, fake_tools):
    analyses, _ = checkouts
    shared = tmp_path / "shared"
    (shared / "image").mkdir(parents=True)
    (shared / "cache/data-managers").mkdir(parents=True)
    (shared / "image/IMAGE.txt").write_text("image_id=" + IMAGE + "\n")
    env = dict(os.environ, SHIELD_HOME=str(shared), SHIELD_STATE_ROOT=str(tmp_path / "runs"),
               SHIELD_SOURCE_DIR=str(analyses), SHIELD_ENGINE="image", FAKE_COMPATIBLE="true")
    result = subprocess.run(["bash", str(SHIELD / "shield-run.sh"), "start", "C.12580", "stage0"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "runtime image's built-in jheem2" in result.stdout
    assert runs(fake_tools, "build") == []
    for args in runs(fake_tools, "model"):
        assert not any("R_PROFILE_USER" in a for a in args)
