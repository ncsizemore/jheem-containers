#!/usr/bin/env python3
"""Preserve committed analysis and engine code and select it once per calibration code.

The registry lives beside run records, not in the mutable input cache. Its
selection applies across locations; a pipeline selects all its codes together.
The team loads jheem2 from source, so a selection also captures the jheem2
checkout (by default the sibling of the analysis checkout); `image` instead
selects the runtime image's built-in engine. No network, Git checkout,
scientific state repair, or package installation.
"""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile


REQUIRED = (
    "applications/SHIELD/R/shield_recorded_runtime.R",
    "applications/SHIELD/shield_calib_setup_and_run.R",
    "applications/SHIELD/check_recorded_completion.R",
)
ENGINE_REQUIRED = ("DESCRIPTION", "NAMESPACE")
IMAGE_ENGINE = "image"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=True)
    return result.stdout.decode().strip()


def read_json(path):
    with path.open() as stream:
        return json.load(stream)


def write_json(path, value):
    # One replace inside the selection lock: a killed writer cannot publish
    # half a pipeline selection. Keep the lock after a hard kill for diagnosis.
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def inventory(tree):
    files = {}
    for path in sorted(tree.rglob("*")):
        if path.is_symlink():
            raise ValueError("source snapshot contains a symlink")
        if path.is_file():
            files[path.relative_to(tree).as_posix()] = digest(path)
        elif not path.is_dir():
            raise ValueError("source snapshot contains a special file")
    return files


def verify_bundle(store, key, name):
    if not re.fullmatch(r"[a-f0-9]{64}", key):
        raise ValueError("invalid " + name + " snapshot identity")
    bundle = store / key
    if bundle.is_symlink():
        raise ValueError(name + " snapshot directory is a symlink")
    metadata_path = bundle / "source.json"
    archive = bundle / "source.tar"
    tree = bundle / name
    if metadata_path.is_symlink() or archive.is_symlink() or tree.is_symlink():
        raise ValueError(name + " snapshot metadata/archive/tree is a symlink")
    metadata = read_json(metadata_path)
    if identity(metadata) != key or metadata["schema_version"] != 1:
        raise ValueError(name + " snapshot metadata changed")
    if digest(archive) != metadata["archive_sha256"]:
        raise ValueError(name + " snapshot archive changed")
    if inventory(tree) != metadata["files"]:
        raise ValueError(name + " snapshot files changed or are missing")
    return tree, metadata["commit"]


def engine_of(selection):
    # Selections saved before engine snapshots used the image's built-in engine.
    return selection.get("engine", IMAGE_ENGINE)


def verify(store, selection):
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", selection["image"]):
        raise ValueError("invalid saved image ID")
    # Census: the manager-build dependency bundle or a census-only release.
    for field, prefix in (("census", "(?:data-managers|census-manager)"), ("syphilis", "syphilis-manager")):
        if not re.fullmatch(prefix + r"-v[0-9]{4}\.[0-9]{2}\.[0-9]{2}([.-][0-9A-Za-z]+)*", selection[field]):
            raise ValueError("invalid saved manager release")
    if not re.fullmatch(r"[0-9]+", str(selection["seed"])):
        raise ValueError("invalid saved seed")
    tree, revision = verify_bundle(store, selection["snapshot"], "jheem_analyses")
    engine = engine_of(selection)
    if engine == IMAGE_ENGINE:
        return tree, revision, None, None
    engine_tree, engine_revision = verify_bundle(store / "engines", engine, "jheem2")
    if not is_jheem2(engine_tree):
        raise ValueError("engine snapshot is not the jheem2 package")
    return tree, revision, engine_tree, engine_revision


def is_jheem2(tree):
    description = tree / "DESCRIPTION"
    return description.is_file() and re.search(r"(?m)^Package:\s*jheem2\s*$", description.read_text()) is not None


def capture(store, source, name="jheem_analyses", required=REQUIRED, label="analysis"):
    repo = Path(git(source, "rev-parse", "--show-toplevel"))
    if git(repo, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError(label + " checkout has uncommitted changes; commit them before a new run")
    revision = git(repo, "rev-parse", "HEAD")
    entries = git(repo, "ls-tree", "-r", revision).splitlines()
    if any(entry.startswith(("120000 ", "160000 ")) for entry in entries):
        raise ValueError("source snapshots do not yet support symlinks or submodules")
    with tempfile.TemporaryDirectory(prefix=".preparing-", dir=store) as temporary:
        bundle = Path(temporary) / "bundle"
        bundle.mkdir()
        archive = bundle / "source.tar"
        with archive.open("wb") as output:
            subprocess.run(["git", "-C", str(repo), "archive", "--format=tar", revision],
                           stdout=output, check=True)
        tree = bundle / name
        tree.mkdir()
        # Extract regular files only; never follow links or accept archive paths
        # outside this new directory. Do not inherit tar ownership or modes.
        with tarfile.open(archive) as source_tar:
            for member in source_tar:
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or ".git" in path.parts:
                    raise ValueError("unsafe path in source archive")
                destination = tree.joinpath(*path.parts)
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with source_tar.extractfile(member) as src, destination.open("xb") as dst:
                        for block in iter(lambda: src.read(1024 * 1024), b""):
                            dst.write(block)
                    try:
                        destination.chmod(0o555 if member.mode & 0o111 else 0o444)
                    except OSError as error:
                        # CIFS may expose mount-wide modes/ownership and reject
                        # chmod. Runtime mounts are read-only on both access
                        # paths; integrity is checked again before each launch.
                        if error.errno not in (errno.EPERM, errno.EOPNOTSUPP):
                            raise
                else:
                    raise ValueError("unsupported entry in source archive")
        if any(not (tree / path).is_file() for path in required):
            if name == "jheem2":
                raise ValueError("jheem2 checkout lacks DESCRIPTION/NAMESPACE")
            raise ValueError("checkout lacks the recorded SHIELD runtime; no ordinary-mode fallback")
        if name == "jheem2" and not is_jheem2(tree):
            raise ValueError("engine checkout is not the jheem2 package")
        if git(repo, "rev-parse", "HEAD") != revision or git(repo, "status", "--porcelain", "--untracked-files=all"):
            raise ValueError(label + " checkout changed during source capture; retry after committing")
        metadata = {"schema_version": 1, "commit": revision,
                    "archive_sha256": digest(archive), "files": inventory(tree)}
        key = identity(metadata)
        write_json(bundle / "source.json", metadata)
        if not (store / key).exists():
            os.rename(bundle, store / key)
        return key


def engine_checkout(source, engine_source):
    if engine_source:
        return Path(engine_source)
    sibling = Path(git(source, "rev-parse", "--show-toplevel")).parent / "jheem2"
    if not sibling.is_dir():
        raise ValueError("no jheem2 checkout next to the analysis checkout (" + str(sibling) + "); "
                         "set SHIELD_JHEEM2_DIR to your jheem2 checkout, or SHIELD_ENGINE=image "
                         "to use the runtime image's built-in jheem2")
    return sibling


def select(root, source, codes, image, census, syphilis, seed, resume=False, expected=None,
           engine_source=None):
    root = Path(root).resolve()
    if any(c in str(root) for c in ("\n", "\t", ",")):
        raise ValueError("state path cannot contain tabs, newlines or commas")
    if not codes or any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", c) for c in codes):
        raise ValueError("invalid calibration code")
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", image):
        raise ValueError("expected a full image ID")
    store = root / "run_sources"
    store.mkdir(parents=True, exist_ok=True)
    lock = store / ".selection-lock"
    try:
        lock.mkdir()
    except FileExistsError:
        raise ValueError("source selection is locked; retry later, or inspect an interrupted setup")
    try:
        path = store / "selections.json"
        registry = read_json(path) if path.exists() else {"schema_version": 1, "calibrations": {}}
        if registry.get("schema_version") != 1 or not isinstance(registry.get("calibrations"), dict):
            raise ValueError("invalid source selection registry")
        saved = registry["calibrations"]
        existing = [saved[c] for c in codes if c in saved]
        if existing and any(item != existing[0] for item in existing):
            raise ValueError("pipeline stages have different saved source/runtime selections")
        for code in codes:
            if code not in saved and (
                (root / "mcmc_runs" / "shield" / code).exists()
                or any((root / "run_records" / "shield").glob("*/" + code))
            ):
                raise ValueError("existing run has no saved source selection; preserve it and use its original runtime")
        if existing:
            selection = existing[0]
            for field, value in (expected or {}).items():
                if str(selection[field]) != str(value):
                    raise ValueError("requested " + field + " differs from the saved run selection")
            if engine_source == IMAGE_ENGINE and engine_of(selection) != IMAGE_ENGINE:
                raise ValueError("requested engine differs from the saved run selection")
        else:
            if resume:
                raise ValueError("resume requires the original saved source selection")
            snapshot = capture(store, source)
            if engine_source == IMAGE_ENGINE:
                engine = IMAGE_ENGINE
            else:
                engines = store / "engines"
                engines.mkdir(exist_ok=True)
                engine = capture(engines, engine_checkout(source, engine_source), "jheem2",
                                 ENGINE_REQUIRED, "jheem2")
            selection = {"snapshot": snapshot, "engine": engine, "image": image,
                         "census": census, "syphilis": syphilis, "seed": str(seed)}
        tree, revision, engine_tree, engine_revision = verify(store, selection)
        if any(code not in saved for code in codes):
            for code in codes:
                saved[code] = selection
            write_json(path, registry)
        return dict(selection, engine=engine_of(selection), path=str(tree), commit=revision,
                    engine_path=str(engine_tree) if engine_tree else "-",
                    engine_commit=engine_revision or "-")
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--source", default=".")
    parser.add_argument("--image", required=True)
    parser.add_argument("--census", required=True)
    parser.add_argument("--syphilis", required=True)
    parser.add_argument("--seed", default="0")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--engine-source", default="",
                        help="jheem2 checkout to capture (default: sibling of the analysis "
                             "checkout), or 'image' for the runtime image's built-in engine")
    parser.add_argument("codes", nargs="+")
    args = parser.parse_args()
    expected = {field: os.environ[env] for field, env in
                (("census", "CENSUS_TAG"), ("syphilis", "SYPHILIS_TAG"), ("seed", "SHIELD_RANDOM_SEED"))
                if env in os.environ}
    try:
        result = select(args.root, args.source, args.codes, args.image, args.census,
                        args.syphilis, args.seed, args.resume, expected,
                        args.engine_source or None)
        # Tab is IFS whitespace in the wrapper, so absent values print as "-".
        print("\t".join(result[key] for key in
                        ("path", "commit", "image", "census", "syphilis", "seed", "snapshot",
                         "engine", "engine_path", "engine_commit")))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, "shield-run source: " + str(error) + "\n")


if __name__ == "__main__":
    main()
