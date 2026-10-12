#!/usr/bin/env python3
"""Shared store of immutable data-manager releases for container runs.

Layout: <store>/<manager>/<release tag>/{<manager>, resolution.json}, the same
layout as an installation's bundled cache, so a run mounts one release
directory at /work/cache/data-managers/<manager>/<tag>. A missing release is
copied from the installation's bundled cache when it has it, or otherwise
downloaded from the GitHub release and checked against the digest GitHub
publishes for the asset. Releases are added once and never replaced: a stored
copy that fails verification stops the launch for an administrator to inspect.
The container checks the digest again when it loads the manager.
"""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


REPOSITORY = "tfojo1/jheem_analyses"
TAGS = {
    # Census: the manager-build dependency bundle or a census-only release.
    "census.manager.rdata": r"(?:data-managers|census-manager)",
    "syphilis.manager.rdata": r"syphilis-manager",
}
DATED = r"-v[0-9]{4}\.[0-9]{2}\.[0-9]{2}([.-][0-9A-Za-z]+)*"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def validate(manager, tag):
    if manager not in TAGS:
        raise ValueError("unknown data manager: " + manager)
    if not re.fullmatch(TAGS[manager] + DATED, tag):
        raise ValueError(manager + " needs an immutable dated release, not " + repr(tag))


def check(directory, manager, tag):
    """Return the verified SHA-256 of a stored or bundled release directory."""
    if directory.is_symlink():
        raise ValueError("release directory must not be a symlink")
    artifact, metadata = directory / manager, directory / "resolution.json"
    if artifact.is_symlink() or metadata.is_symlink():
        raise ValueError("release files must not be symlinks")
    resolution = json.loads(metadata.read_text())
    expected = str(resolution.get("sha256", ""))
    if (resolution.get("repository") != REPOSITORY or resolution.get("manager") != manager
            or resolution.get("resolved_tag") != tag or not re.fullmatch(r"[0-9a-f]{64}", expected)):
        raise ValueError("release record does not identify " + manager + " " + tag)
    if digest(artifact) != expected:
        raise ValueError(manager + " " + tag + " fails SHA-256 verification")
    return expected


def github_release(tag):
    request = Request("https://api.github.com/repos/" + REPOSITORY + "/releases/tags/" + tag,
                      headers={"Accept": "application/vnd.github+json",
                               "User-Agent": "jheem-shield-manager-store"})
    with urlopen(request, timeout=60) as response:
        return json.load(response)


def download(tag, manager, destination):
    release = github_release(tag)
    assets = [a for a in release.get("assets", []) if a.get("name") == manager]
    if len(assets) != 1:
        raise ValueError("release " + tag + " does not have exactly one " + manager)
    published = str(assets[0].get("digest") or "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", published):
        raise ValueError("release " + tag + " does not publish a SHA-256 digest for " + manager)
    request = Request(assets[0]["browser_download_url"],
                      headers={"User-Agent": "jheem-shield-manager-store"})
    with urlopen(request, timeout=600) as response, (destination / manager).open("xb") as output:
        shutil.copyfileobj(response, output, 1024 * 1024)
    expected = published.removeprefix("sha256:")
    if digest(destination / manager) != expected:
        raise ValueError("downloaded " + manager + " " + tag + " does not match its published digest")
    return {"schema_version": 1, "manager": manager, "repository": REPOSITORY,
            "requested_tag": tag, "resolved_tag": tag, "asset": manager,
            "sha256": expected, "published_at": release.get("published_at")}


def read_only(path):
    try:
        path.chmod(0o444)
    except OSError as error:
        # CIFS exposes mount-wide modes; integrity rests on the digest checks.
        if error.errno not in (errno.EPERM, errno.EOPNOTSUPP):
            raise


def ensure(store, manager, tag, bundled=None):
    """Make <store>/<manager>/<tag> present and verified; return its path."""
    validate(manager, tag)
    target = Path(store) / manager / tag
    if target.exists() or target.is_symlink():
        check(target, manager, tag)
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".incoming-", dir=target.parent) as temporary:
        staged = Path(temporary) / tag
        staged.mkdir()
        source = Path(bundled) / "data-managers" / manager / tag if bundled else None
        if source is not None and source.is_dir():
            check(source, manager, tag)
            for name in (manager, "resolution.json"):
                shutil.copyfile(source / name, staged / name)
        else:
            resolution = download(tag, manager, staged)
            (staged / "resolution.json").write_text(json.dumps(resolution, indent=2) + "\n")
        check(staged, manager, tag)
        for name in (manager, "resolution.json"):
            read_only(staged / name)
        try:
            os.rename(staged, target)
        except OSError as error:
            # Another launch stored it first; use that copy once it verifies.
            if not target.is_dir() or error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                raise
    check(target, manager, tag)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store", required=True)
    parser.add_argument("--bundled", help="an installation's bundled cache to copy from first")
    parser.add_argument("manager")
    parser.add_argument("tag")
    args = parser.parse_args()
    try:
        print(ensure(args.store, args.manager, args.tag, args.bundled))
    except HTTPError as error:
        parser.exit(1, f"shield-run inputs: GitHub returned {error.code} for {args.manager} "
                       f"{args.tag}; no calibration was launched.\n")
    except (URLError, TimeoutError) as error:
        parser.exit(1, f"shield-run inputs: could not reach GitHub for {args.manager} {args.tag} "
                       f"({error}); no calibration was launched.\n")
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        parser.exit(1, "shield-run inputs: " + str(error) + "; no calibration was launched.\n")


if __name__ == "__main__":
    main()
