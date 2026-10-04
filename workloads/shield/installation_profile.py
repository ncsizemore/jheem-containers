#!/usr/bin/env python3
"""Bind a SHIELD pilot installation to its tested image and immutable inputs.

Prepare after downloading the image and materializing its selected input cache.
The wrapper reads this data as JSON, never as executable shell configuration.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile


MANAGERS = ("census.manager.rdata", "syphilis.manager.rdata")
FIELDS = ("image_id", "image_tag", "workflow_run", "containers_commit",
          "jheem_analyses_ref", "jheem2_ref", "input_profile", "census_tag",
          "syphilis_tag", "random_seed")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"missing or symlinked installation file: {path}")
    return path


def metadata(home):
    values = {}
    checksum = None
    for line in regular(home / "image/IMAGE.txt").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in values:
                raise ValueError(f"duplicate image metadata: {key}")
            values[key] = value
        elif line.strip():
            match = re.fullmatch(r"([0-9a-f]{64})  jheem-shield-recorded\.tar\.gz", line)
            if not match or checksum:
                raise ValueError("invalid image archive checksum line")
            checksum = match[1]
    if not all(values.get(key) for key in FIELDS) or not checksum:
        raise ValueError("incomplete tested image metadata; use a uniquely tagged pilot export")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", values["image_id"]):
        raise ValueError("invalid image ID")
    if not re.fullmatch(r"[0-9]+", values["workflow_run"]):
        raise ValueError("invalid workflow run")
    expected_tag = "docker.io/library/jheem-shield:pilot-r" + values["workflow_run"]
    if values["image_tag"] != expected_tag:
        raise ValueError("image tag must be unique to the tested workflow run")
    for key in ("containers_commit", "jheem_analyses_ref", "jheem2_ref"):
        if not re.fullmatch(r"[0-9a-f]{40}", values[key]):
            raise ValueError(f"invalid source commit: {key}")
    for key, prefix in (("census_tag", "data-managers-v"),
                        ("syphilis_tag", "syphilis-manager-v")):
        if not re.fullmatch(re.escape(prefix) + r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}", values[key]):
            raise ValueError(f"not an immutable manager release: {key}")
    if not re.fullmatch(r"[0-9]+", values["random_seed"]):
        raise ValueError("invalid random seed")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,80}", values["input_profile"]):
        raise ValueError("invalid input profile")
    return values, checksum


def validate_profile(profile, values, checksum):
    if not isinstance(profile, dict) or profile.get("schema_version") != 1:
        raise ValueError("unsupported installation profile")
    if profile.get("image") != values or profile.get("archive_sha256") != checksum:
        raise ValueError("installation profile differs from tested image metadata")
    namespace = profile.get("state_namespace", "")
    if not isinstance(namespace, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,120}", namespace):
        raise ValueError("invalid isolated state namespace")
    inputs = profile.get("inputs")
    if not isinstance(inputs, list) or len(inputs) != 2:
        raise ValueError("installation must identify both managers")
    for entry, manager, key in zip(inputs, MANAGERS, ("census_tag", "syphilis_tag")):
        if (not isinstance(entry, dict) or entry.get("manager") != manager
                or entry.get("tag") != values[key]
                or not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", "")))):
            raise ValueError("invalid installation manager identity")
    return profile


def read_profile(home):
    values, checksum = metadata(home)
    profile = json.loads(regular(home / "installation.json").read_text())
    return validate_profile(profile, values, checksum)


def verify_inputs(home, profile):
    for entry in profile["inputs"]:
        directory = home / "cache/data-managers" / entry["manager"] / entry["tag"]
        if directory.is_symlink():
            raise ValueError("manager directory must not be a symlink")
        artifact = regular(directory / entry["manager"])
        resolution = json.loads(regular(directory / "resolution.json").read_text())
        if (resolution.get("repository") != "tfojo1/jheem_analyses"
                or resolution.get("manager") != entry["manager"]
                or resolution.get("resolved_tag") != entry["tag"]
                or resolution.get("sha256") != entry["sha256"]
                or digest(artifact) != entry["sha256"]):
            raise ValueError(f"manager identity/digest mismatch: {entry['manager']}")


def prepare(home, namespace=None):
    target = home / "installation.json"
    if target.exists() or target.is_symlink():
        raise ValueError("preserve the existing installation profile; use a new installation")
    values, checksum = metadata(home)
    archive = regular(home / "image/jheem-shield-recorded.tar.gz")
    if digest(archive) != checksum:
        raise ValueError("image archive checksum mismatch")
    # docker save preserves tags. Refuse an archive that could retag another pilot.
    with tarfile.open(archive, "r:gz") as saved:
        info = saved.getmember("manifest.json")
        if not info.isfile() or info.size > 1024 * 1024:
            raise ValueError("invalid Docker archive manifest")
        manifest = json.load(saved.extractfile(info))
    expected_tag = values["image_tag"].removeprefix("docker.io/library/")
    if (not isinstance(manifest, list) or len(manifest) != 1 or not isinstance(manifest[0], dict)
            or manifest[0].get("RepoTags") != [expected_tag]):
        raise ValueError("archive must contain only its unique pilot tag")
    inputs = []
    for manager, key in zip(MANAGERS, ("census_tag", "syphilis_tag")):
        directory = home / "cache/data-managers" / manager / values[key]
        resolution = json.loads(regular(directory / "resolution.json").read_text())
        inputs.append({"manager": manager, "tag": values[key], "sha256": resolution.get("sha256")})
    profile = {"schema_version": 1, "image": values, "archive_sha256": checksum,
               "state_namespace": namespace or "shield-container-r" + values["workflow_run"],
               "inputs": inputs}
    validate_profile(profile, values, checksum)
    verify_inputs(home, profile)
    # Verify before exclusive creation; never overwrite an installed selection.
    with target.open("x") as output:
        json.dump(profile, output, indent=2)
        output.write("\n")
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "show", "verify"))
    parser.add_argument("home", type=Path)
    parser.add_argument("--state-namespace")
    args = parser.parse_args()
    try:
        home = args.home.resolve()
        profile = (prepare(home, args.state_namespace) if args.command == "prepare"
                   else read_profile(home))
        if args.command == "verify":
            verify_inputs(home, profile)
        values = profile["image"]
        print("\t".join((values["image_id"], profile["state_namespace"],
                          values["census_tag"], values["syphilis_tag"], values["random_seed"])))
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        print(f"SHIELD installation: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
