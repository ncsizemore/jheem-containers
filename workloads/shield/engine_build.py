#!/usr/bin/env python3
"""Build a captured jheem2 snapshot once per runtime image, and reuse it.

The build runs in the selected image (its R, compilers, and dependencies) and is
keyed by engine snapshot and image ID. A finished build is verified file by file
before every use; a damaged build is refused rather than silently rebuilt.
Concurrent launches of the same build wait for the first to finish.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

from source_snapshot import inventory, read_json, write_json, verify_bundle, is_jheem2


SCHEMA = 1
MARKER = "SHIELD-ENGINE.txt"


def build_key(engine, image):
    payload = {"schema_version": SCHEMA, "engine": engine, "image": image}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def verify_build(directory, engine, image, commit):
    metadata = read_json(directory / "build.json")
    if (metadata.get("schema_version") != SCHEMA or metadata.get("engine") != engine
            or metadata.get("image") != image or metadata.get("engine_commit") != commit):
        raise ValueError("engine build metadata does not match the run selection: " + str(directory))
    library = directory / "library"
    if library.is_symlink() or inventory(library) != metadata["files"]:
        raise ValueError("engine build files changed or are missing; preserve it for inspection: " + str(directory))
    return library


def on_cifs(path):
    result = subprocess.run(["stat", "-f", "-c", "%T", str(path)], capture_output=True, text=True)
    return result.stdout.strip() in ("cifs", "smb2", "smb3")


def mount(source, target, readonly=False, relabel=True):
    options = "type=bind,src=" + str(source) + ",dst=" + target
    if readonly:
        options += ",readonly"
    if relabel and not on_cifs(source):
        options += ",relabel=shared"
    return ["--mount", options]


def run_build(engine_tree, library, image, script_dir, log):
    command = ["podman", "run", "--rm", "--userns=keep-id", "--group-add", "keep-groups",
               "--network", "none", "--user", str(os.getuid()) + ":" + str(os.getgid())]
    command += mount(engine_tree, "/opt/run-engine/jheem2", readonly=True)
    command += mount(library, "/opt/run-engine/build")
    # Installed helper files carry their SELinux label from installation.
    command += mount(Path(script_dir) / "build_engine.sh", "/opt/shield/build_engine.sh",
                     readonly=True, relabel=False)
    command += [image, "shell", "/opt/shield/build_engine.sh"]
    with log.open("w") as output:
        return subprocess.run(command, stdout=output, stderr=subprocess.STDOUT).returncode


def ensure(root, engine, image, script_dir, wait_seconds=1800, poll_seconds=10):
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", image):
        raise ValueError("expected a full image ID")
    store = Path(root).resolve() / "run_sources"
    engine_tree, commit = verify_bundle(store / "engines", engine, "jheem2")
    if not is_jheem2(engine_tree):
        raise ValueError("engine snapshot is not the jheem2 package")
    builds = store / "engine-builds"
    builds.mkdir(parents=True, exist_ok=True)
    final = builds / build_key(engine, image)
    lock = builds / (".lock-" + final.name)
    deadline = time.monotonic() + wait_seconds
    while True:
        if final.exists():
            return verify_build(final, engine, image, commit)
        try:
            lock.mkdir()
            break
        except FileExistsError:
            if time.monotonic() > deadline:
                raise ValueError("another launch has been building this engine for too long; "
                                 "inspect " + str(lock))
            print("Waiting for another launch to finish building jheem2 " + commit[:8] + "...",
                  file=sys.stderr)
            time.sleep(poll_seconds)
    try:
        if final.exists():
            return verify_build(final, engine, image, commit)
        print("Building jheem2 " + commit[:8] + " for this runtime (about two minutes, once per engine version)...",
              file=sys.stderr)
        with tempfile.TemporaryDirectory(prefix=".building-", dir=builds) as temporary:
            staging = Path(temporary) / "build"
            library = staging / "library"
            library.mkdir(parents=True)
            # Compiler output goes to a log kept with the build, or kept beside
            # the builds and shown when the build fails.
            log = staging / "build.log"
            if run_build(engine_tree, library, image, script_dir, log) != 0:
                kept = builds / ("failed-" + final.name[:16] + "-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + ".log")
                os.replace(log, kept)
                print("".join(kept.read_text().splitlines(keepends=True)[-30:]), file=sys.stderr)
                raise ValueError("the jheem2 build failed; no calibration was launched. Full log: " + str(kept))
            package = library / "jheem2"
            if not (package / "DESCRIPTION").is_file():
                raise ValueError("engine build produced no jheem2 package")
            (package / MARKER).write_text(
                "engine_commit: " + commit + "\nengine_snapshot: " + engine + "\nimage: " + image + "\n")
            write_json(staging / "build.json", {
                "schema_version": SCHEMA, "engine": engine, "engine_commit": commit, "image": image,
                "built_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "files": inventory(library)})
            os.rename(staging, final)
        return verify_build(final, engine, image, commit)
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--engine", required=True, help="engine snapshot identity")
    parser.add_argument("--image", required=True)
    parser.add_argument("--script-dir", default=str(Path(__file__).resolve().parent))
    args = parser.parse_args()
    try:
        print(ensure(args.root, args.engine, args.image, args.script_dir))
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, "shield-run engine: " + str(error) + "\n")


if __name__ == "__main__":
    main()
