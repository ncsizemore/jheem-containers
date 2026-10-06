import json
import os
from pathlib import Path
import subprocess
import sys
import time

import pytest


SHIELD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHIELD))
import source_snapshot as snap  # noqa: E402

IMAGE = "sha256:" + "a" * 64

# Stands in for podman. A detached pipeline "runs" for FAKE_RUN_POLLS status
# checks, then exits 0 (or 1 for a location named in FAKE_FAIL). Each launch logs
# how many pipelines were already running, so tests can check the batch limit.
FAKE_PODMAN = r'''import json, os, sys
args = sys.argv[1:]
state = os.environ["FAKE_STATE"]
os.makedirs(state, exist_ok=True)
with open(os.path.join(state, "calls.jsonl"), "a") as stream:
    stream.write(json.dumps(args) + "\n")

def path(name):
    return os.path.join(state, name + ".json")

def load(name):
    with open(path(name)) as stream:
        return json.load(stream)

def save(name, value):
    with open(path(name), "w") as stream:
        json.dump(value, stream)

def running():
    return [f for f in os.listdir(state) if f.startswith("shield-") and load(f[:-5])["left"] > 0]

if args[:2] == ["image", "inspect"]:
    print("a" * 64)
elif args[0] == "run" and "/opt/shield/build_engine.sh" in args:
    target = next(a.split("src=")[1].split(",")[0] for a in args
                  if a.startswith("type=bind") and "dst=/opt/run-engine/build" in a)
    os.makedirs(os.path.join(target, "jheem2"))
    open(os.path.join(target, "jheem2", "DESCRIPTION"), "w").write("Package: jheem2\n")
elif args[0] == "run" and "--rm" in args:
    pass
elif args[0] == "run" and "-d" in args:
    name = args[args.index("--name") + 1]
    location = args[-len(args) + args.index("pipeline") + 1]
    with open(os.path.join(state, "launches.log"), "a") as stream:
        stream.write("%s %d\n" % (location, len(running())))
    save(name, {"left": int(os.environ.get("FAKE_RUN_POLLS", "2")),
                "exit": 1 if location in os.environ.get("FAKE_FAIL", "").split(",") else 0})
elif args[:2] == ["container", "inspect"]:
    name = args[-1]
    if not os.path.exists(path(name)):
        sys.exit(1)
    value = load(name)
    if "{{.State.Running}}" in args:
        if value["left"] > 0:
            value["left"] -= 1
            save(name, value)
            print("true")
        else:
            print("false")
    else:
        print(value["exit"])
elif args[0] == "ps" and any(a.startswith("label=shield.batch=") for a in args):
    for f in running():
        print(f[:-5])
elif args[0] == "stop":
    value = load(args[-1])
    value.update(left=0, exit=137)
    save(args[-1], value)
elif args[0] == "ps":
    pass
else:
    sys.exit(97)
'''


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args]).decode().strip()


def make_repo(path, files):
    path.mkdir()
    git(path, "init", "-q")
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "Batch test")
    for name, text in files.items():
        (path / name).parent.mkdir(parents=True, exist_ok=True)
        (path / name).write_text(text)
    git(path, "add", ".")
    git(path, "commit", "-qm", "initial")


@pytest.fixture
def env(tmp_path):
    make_repo(tmp_path / "jheem_analyses", {**{name: "# fixture\n" for name in snap.REQUIRED}})
    make_repo(tmp_path / "jheem2", {"DESCRIPTION": "Package: jheem2\n", "NAMESPACE": "\n"})
    shared = tmp_path / "shared"
    (shared / "image").mkdir(parents=True)
    (shared / "cache/data-managers").mkdir(parents=True)
    (shared / "image/IMAGE.txt").write_text("image_id=" + IMAGE + "\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    (binary / "podman").write_text("#!" + sys.executable + "\n" + FAKE_PODMAN)
    for name, body in (("loginctl", "echo yes"), ("stat", "echo ext2"), ("tac", "cat")):
        (binary / name).write_text("#!/bin/sh\n" + body + "\n")
    for tool in binary.iterdir():
        tool.chmod(0o755)
    return dict(os.environ, SHIELD_HOME=str(shared), SHIELD_STATE_ROOT=str(tmp_path / "runs"),
                SHIELD_SOURCE_DIR=str(tmp_path / "jheem_analyses"), FAKE_STATE=str(tmp_path / "podman"),
                SHIELD_BATCH_POLL_SECONDS="0.1", PATH=str(binary) + os.pathsep + os.environ["PATH"])


def shield_run(env, *args, **extra):
    return subprocess.run(["bash", str(SHIELD / "shield-run.sh"), *args], env=dict(env, **extra),
                          capture_output=True, text=True)


def finished_batch(env, timeout=60):
    batches = Path(env["SHIELD_STATE_ROOT"]) / "run_batches"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        logs = list(batches.glob("*/batch.log"))
        if logs and "finished\n" in logs[0].read_text().split("] batch ")[-1]:
            return logs[0].parent
        time.sleep(0.1)
    raise AssertionError("batch did not finish: " + "".join(p.read_text() for p in batches.glob("*/batch.log")))


def calls(env):
    lines = (Path(env["FAKE_STATE"]) / "calls.jsonl").read_text().splitlines()
    return [json.loads(line) for line in lines]


def test_batch_runs_every_location_within_the_limit(env):
    cities = ["C.12580", "C.35620", "C.12060", "C.16980", "C.26420"]
    result = shield_run(env, "batch", ",".join(cities), "stage0", "stage1", SHIELD_MAX_CITIES="2")
    assert result.returncode == 0, result.stderr
    assert "Started batch" in result.stdout
    batch = finished_batch(env)
    launches = (Path(env["FAKE_STATE"]) / "launches.log").read_text().split()
    assert sorted(launches[0::2]) == sorted(cities)
    assert max(int(n) for n in launches[1::2]) <= 1  # never a third while two run
    status = (batch / "status.txt").read_text()
    assert all(f"{city} finished (exit 0)" in status for city in cities)
    # One compatibility check and one engine build for the whole batch.
    runs = [a for a in calls(env) if a[0] == "run"]
    assert len([a for a in runs if "--rm" in a and "/opt/shield/build_engine.sh" not in a]) == 1
    assert len([a for a in runs if "/opt/shield/build_engine.sh" in a]) == 1
    detached = [a for a in runs if "-d" in a]
    assert all("shield.batch=" + batch.name in a for a in detached)
    # Each container runs the whole pipeline for its own location.
    assert sorted(a[a.index("pipeline") + 1] for a in detached) == sorted(cities)
    assert all(a[a.index("pipeline") + 2:] == ["stage0", "stage1"] for a in detached)


def test_status_counts_failures_and_bad_input_is_refused(env):
    result = shield_run(env, "batch", "C.12580,C.35620", "stage0", FAKE_FAIL="C.35620")
    assert result.returncode == 0, result.stderr
    batch = finished_batch(env)
    status = shield_run(env, "status")
    assert f"batch {batch.name}: done (1 failed, 1 finished)" in status.stdout
    assert "listed twice" in shield_run(env, "batch", "C.12580,C.12580", "stage0").stderr
    assert "invalid location" in shield_run(env, "batch", "C.12580,../x", "stage0").stderr
    assert "positive integer" in shield_run(env, "batch", "C.12580", "stage0",
                                            SHIELD_MAX_CITIES="0").stderr


def test_location_with_unrecorded_state_is_refused_up_front(env):
    (Path(env["SHIELD_STATE_ROOT"]) / "mcmc_runs/shield/stage0/C.35620").mkdir(parents=True)
    result = shield_run(env, "batch", "C.12580,C.35620", "stage0")
    assert result.returncode == 1
    assert "stage0 for C.35620 has saved results" in result.stderr
    assert not (Path(env["SHIELD_STATE_ROOT"]) / "run_batches").exists()


def test_stop_batch_stops_the_scheduler_and_its_running_locations(env):
    result = shield_run(env, "batch", "C.12580,C.35620,C.12060", "stage0",
                        SHIELD_MAX_CITIES="1", FAKE_RUN_POLLS="100000", SHIELD_BATCH_POLL_SECONDS="0.2")
    assert result.returncode == 0, result.stderr
    batches = Path(env["SHIELD_STATE_ROOT"]) / "run_batches"
    deadline = time.monotonic() + 30
    while not (Path(env["FAKE_STATE"]) / "launches.log").exists() and time.monotonic() < deadline:
        time.sleep(0.1)
    batch = next(batches.iterdir())
    assert "scheduling" in shield_run(env, "status").stdout
    stopped = shield_run(env, "stop-batch", batch.name)
    assert stopped.returncode == 0, stopped.stderr
    assert "Stopped shield-pipeline-stage0-C.12580" in stopped.stdout
    time.sleep(0.5)
    assert "scheduling" not in shield_run(env, "status").stdout
    # Only the first location ever started.
    assert (Path(env["FAKE_STATE"]) / "launches.log").read_text().split()[0::2] == ["C.12580"]
