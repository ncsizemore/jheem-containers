import importlib.util
import errno
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest


MODULE = Path(__file__).resolve().parents[1] / "source_snapshot.py"
spec = importlib.util.spec_from_file_location("source_snapshot", MODULE)
snap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snap)
IMAGE = "sha256:" + "a" * 64


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args]).decode().strip()


@pytest.fixture
def repo(tmp_path):
    repo = tmp_path / "checkout"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "test@example.invalid")
    git(repo, "config", "user.name", "Snapshot test")
    for name in snap.REQUIRED:
        target = repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("# recorded test fixture\n")
    (repo / "model.R").write_text("parameter <- 1\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "initial model")
    return repo


def select(root, repo, codes=("stage0",), engine_source="image", census="data-managers-v2026.08.26",
           **kwargs):
    return snap.select(root, repo, codes, IMAGE, census,
                       "syphilis-manager-v2026.07.27", "0", engine_source=engine_source, **kwargs)


@pytest.mark.parametrize("census,valid", [("census-manager-v2026.10.08", True),
                                          ("census-manager-latest", False),
                                          ("syphilis-manager-v2026.09.09", False)])
def test_census_may_come_from_a_census_only_release(tmp_path, repo, census, valid):
    if valid:
        select(tmp_path / "runs", repo, census=census)
        registry = json.loads((tmp_path / "runs/run_sources/selections.json").read_text())
        assert registry["calibrations"]["stage0"]["census"] == census
    else:
        with pytest.raises(ValueError, match="manager release"):
            select(tmp_path / "runs", repo, census=census)


@pytest.fixture
def engine(tmp_path):
    # A jheem2 checkout beside the analysis checkout, as on the team servers.
    engine = tmp_path / "jheem2"
    engine.mkdir()
    git(engine, "init", "-q")
    git(engine, "config", "user.email", "test@example.invalid")
    git(engine, "config", "user.name", "Snapshot test")
    (engine / "DESCRIPTION").write_text("Package: jheem2\nVersion: 1.12.3.9000\n")
    (engine / "NAMESPACE").write_text("export(run)\n")
    (engine / "R").mkdir()
    (engine / "R/engine.R").write_text("run <- function() 1\n")
    git(engine, "add", ".")
    git(engine, "commit", "-qm", "engine")
    return engine


def test_new_definition_without_rebuild_and_old_selection_after_checkout_moves(tmp_path, repo):
    root = tmp_path / "runs"
    first = select(root, repo, ("stage0", "stage1"))
    (repo / "model.R").write_text("parameter <- 2\n")
    git(repo, "commit", "-qam", "new calibration")
    # Another location or pipeline resume must not pick up the moving checkout.
    same = select(root, repo, ("stage0", "stage1"), resume=True)
    assert same == first
    assert (Path(same["path"]) / "model.R").read_text() == "parameter <- 1\n"
    second = select(root, repo, ("new.stage0",))
    assert second["image"] == first["image"]
    assert second["commit"] != first["commit"]
    assert (Path(second["path"]) / "model.R").read_text() == "parameter <- 2\n"
    # Resume requires neither the original checkout nor network/Git access.
    assert select(root, tmp_path / "absent", ("stage0",), resume=True) == first


@pytest.mark.parametrize("damage", ["file", "missing", "archive", "metadata", "extra", "symlink"])
def test_changed_or_missing_snapshot_is_rejected(tmp_path, repo, damage):
    root = tmp_path / "runs"
    selected = select(root, repo)
    tree = Path(selected["path"])
    if damage == "file":
        (tree / "model.R").chmod(0o644)
        (tree / "model.R").write_text("changed\n")
    elif damage == "missing":
        (tree / "model.R").unlink()
    elif damage == "archive":
        (tree.parent / "source.tar").write_bytes(b"changed")
    elif damage == "metadata":
        (tree.parent / "source.json").write_text("{}")
    elif damage == "extra":
        (tree / "extra.R").write_text("surprise")
    else:
        (tree / "outside").symlink_to(repo / "model.R")
    with pytest.raises((ValueError, KeyError)):
        select(root, repo, resume=True)


@pytest.mark.parametrize("dirty", ["modified", "untracked", "staged"])
def test_dirty_source_is_not_silently_ignored(tmp_path, repo, dirty):
    target = repo / ("untracked.R" if dirty == "untracked" else "model.R")
    target.write_text("changed\n")
    if dirty == "staged":
        git(repo, "add", ".")
    with pytest.raises(ValueError, match="uncommitted"):
        select(tmp_path / "runs", repo)


def test_pipeline_reuses_one_selection_and_rejects_mixed_selections(tmp_path, repo):
    root = tmp_path / "runs"
    first = select(root, repo)
    (repo / "model.R").write_text("parameter <- 2\n")
    git(repo, "commit", "-qam", "update")
    assert select(root, repo, ("stage0", "stage1")) == first
    select(root, repo, ("other",))
    with pytest.raises(ValueError, match="different saved"):
        select(root, repo, ("stage0", "other"))


def test_preserves_legacy_state_and_missing_registry(tmp_path, repo):
    root = tmp_path / "runs"
    (root / "mcmc_runs/shield/stage0/C.12580").mkdir(parents=True)
    with pytest.raises(ValueError, match="original runtime"):
        select(root, repo)
    with pytest.raises(ValueError, match="original saved"):
        select(root, repo, ("stage1",), resume=True)


def test_explicit_input_change_is_rejected_on_reuse(tmp_path, repo):
    root = tmp_path / "runs"
    select(root, repo)
    with pytest.raises(ValueError, match="requested seed"):
        select(root, repo, expected={"seed": "99"})


def test_locked_selection_cannot_be_overwritten(tmp_path, repo):
    root = tmp_path / "runs"
    lock = root / "run_sources/.selection-lock"
    lock.mkdir(parents=True)
    with pytest.raises(ValueError, match="locked"):
        select(root, repo)
    assert lock.is_dir()


def test_mount_wide_permissions_do_not_prevent_capture(tmp_path, repo, monkeypatch):
    def no_chmod(self, mode):
        raise OSError(errno.EPERM, "mount-wide permissions")
    monkeypatch.setattr(Path, "chmod", no_chmod)
    selected = select(tmp_path / "runs", repo)
    assert select(tmp_path / "runs", repo, resume=True) == selected


def test_symlinks_and_missing_recorded_runtime_are_rejected(tmp_path, repo):
    (repo / "link").symlink_to("model.R")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "symlink")
    with pytest.raises(ValueError, match="symlinks"):
        select(tmp_path / "runs", repo)
    (repo / "link").unlink()
    (repo / snap.REQUIRED[0]).unlink()
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "missing runtime")
    with pytest.raises(ValueError, match="no ordinary-mode fallback"):
        select(tmp_path / "runs", repo)


@pytest.mark.parametrize("compatible", [True, False])
def test_wrapper_mounts_saved_source_and_checks_before_launch(tmp_path, repo, compatible):
    shared = tmp_path / "shared"
    (shared / "image").mkdir(parents=True)
    (shared / "cache/data-managers").mkdir(parents=True)
    (shared / "image/IMAGE.txt").write_text("image_id=" + IMAGE + "\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    log = tmp_path / "podman.jsonl"
    podman = binary / "podman"
    podman.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args[:2] == ["image", "inspect"]:
    print("a" * 64)
elif args[0] == "run":
    if "--rm" in args and os.environ["FAKE_COMPATIBLE"] == "false":
        sys.exit(37)
    print("fake-container")
elif args[0] != "ps":
    sys.exit(97)
''')
    podman.chmod(0o755)
    for name, body in (("loginctl", "echo yes"), ("stat", "echo ext2"), ("tac", "cat")):
        path = binary / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    state = tmp_path / "runs"
    # Selection predates checkout edits. The actual wrapper must reuse it.
    chosen = select(state, repo)
    (repo / "model.R").write_text('stop("must not use the changed checkout")\n')
    env = dict(os.environ, SHIELD_HOME=str(shared), SHIELD_STATE_ROOT=str(state),
               SHIELD_SOURCE_DIR=str(repo), FAKE_LOG=str(log),
               FAKE_COMPATIBLE=str(compatible).lower(),
               PATH=str(binary) + os.pathsep + os.environ["PATH"])
    result = subprocess.run(["bash", str(MODULE.parent / "shield-run.sh"),
                             "start", "C.12580", "stage0"],
                            env=env, capture_output=True, text=True)
    assert result.returncode == (0 if compatible else 1), result.stderr
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    runs = [args for args in calls if args[0] == "run"]
    assert len(runs) == (2 if compatible else 1)
    assert "--rm" in runs[0]
    if compatible:
        assert "-d" in runs[1]
    for args in runs:
        assert "JHEEM_ANALYSES_REF=" + chosen["commit"] in args
        assert "SHIELD_IMAGE_ID=" + IMAGE in args
        assert "type=bind,src=" + chosen["path"] + ",dst=/opt/run-source/jheem_analyses,readonly,relabel=shared" in args
        assert f"type=bind,src={state}/run_sources,dst=/work/state/run_sources,readonly,relabel=shared" in args
        assert str(repo) not in " ".join(args)
    assert not list((state / "run_locks").iterdir())


def test_engine_is_captured_from_the_sibling_and_reused_after_it_moves(tmp_path, repo, engine):
    root = tmp_path / "runs"
    first = select(root, repo, ("stage0", "stage1"), engine_source=None)
    assert first["engine"] != "image"
    assert first["engine_commit"] == git(engine, "rev-parse", "HEAD")
    (engine / "R/engine.R").write_text("run <- function() 2\n")
    git(engine, "commit", "-qam", "engine change")
    same = select(root, repo, ("stage0", "stage1"), engine_source=None, resume=True)
    assert same == first
    assert (Path(same["engine_path"]) / "R/engine.R").read_text() == "run <- function() 1\n"
    newer = select(root, repo, ("new.stage0",), engine_source=None)
    assert newer["engine_commit"] == git(engine, "rev-parse", "HEAD")
    assert (Path(newer["engine_path"]) / "R/engine.R").read_text() == "run <- function() 2\n"


def test_missing_engine_checkout_names_both_choices(tmp_path, repo):
    with pytest.raises(ValueError, match="SHIELD_JHEEM2_DIR.*SHIELD_ENGINE=image"):
        select(tmp_path / "runs", repo, engine_source=None)


def test_dirty_or_wrong_engine_is_refused(tmp_path, repo, engine):
    (engine / "scratch.R").write_text("x <- 1\n")
    with pytest.raises(ValueError, match="jheem2 checkout has uncommitted"):
        select(tmp_path / "runs", repo, engine_source=None)
    (engine / "scratch.R").unlink()
    (engine / "DESCRIPTION").write_text("Package: other\n")
    git(engine, "commit", "-qam", "not jheem2")
    with pytest.raises(ValueError, match="not the jheem2 package"):
        select(tmp_path / "runs", repo, ("other.stage0",), engine_source=None)


def test_damaged_engine_snapshot_is_rejected(tmp_path, repo, engine):
    root = tmp_path / "runs"
    chosen = select(root, repo, engine_source=None)
    target = Path(chosen["engine_path"]) / "R/engine.R"
    target.chmod(0o644)
    target.write_text("changed\n")
    with pytest.raises(ValueError, match="jheem2 snapshot files changed"):
        select(root, repo, resume=True, engine_source=None)


def test_selection_without_engine_keeps_the_image_engine(tmp_path, repo, engine):
    root = tmp_path / "runs"
    select(root, repo, engine_source=None)
    registry_path = root / "run_sources/selections.json"
    registry = json.loads(registry_path.read_text())
    # Selections saved before engine snapshots used the image's built-in engine.
    del registry["calibrations"]["stage0"]["engine"]
    registry_path.write_text(json.dumps(registry))
    legacy = select(root, repo, resume=True, engine_source=None)
    assert (legacy["engine"], legacy["engine_path"], legacy["engine_commit"]) == ("image", "-", "-")


def test_requesting_the_image_engine_for_a_captured_run_is_refused(tmp_path, repo, engine):
    root = tmp_path / "runs"
    select(root, repo, engine_source=None)
    with pytest.raises(ValueError, match="requested engine differs"):
        select(root, repo, resume=True, engine_source="image")
