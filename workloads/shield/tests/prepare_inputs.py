#!/usr/bin/env python3
"""Materialize the small, immutable input set used by SHIELD CI.

This is test infrastructure, not a runtime downloader. Recorded containers mount
the resulting cache read-only and run without network access.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from urllib.request import Request, urlopen


REPOSITORY = "tfojo1/jheem_analyses"
INPUTS = (
    {
        "manager": "census.manager.rdata",
        "tag": "data-managers-v2026.08.26",
        "sha256": "f8c710684ccfdfb3a5c8e6f4b54caf0417ab67afb82b89ab3259c4b8151e1053",
        "published_at": "2026-08-26T19:50:47Z",
    },
    {
        "manager": "syphilis.manager.rdata",
        "tag": "syphilis-manager-v2026.07.27",
        "sha256": "0d9bf7e02d58554a52844bdce85e0506c99aec27ac578d052f6b4d2eb89339eb",
        "published_at": "2026-07-27T19:57:12Z",
    },
)

# An identified comparison input, not a change to the installed pilot default.
NATIVE_OCTOBER_INPUTS = (
    INPUTS[0],
    {
        "manager": "syphilis.manager.rdata",
        "tag": "syphilis-manager-v2026.05.05",
        "sha256": "e8acbeb758ae4af4e149a62ef78c862a114a2d55f43a0c4695f49d9a8a9fa0e6",
        "published_at": "2026-05-05T16:36:49Z",
    },
)
SEPTEMBER_INPUTS = (
    INPUTS[0],
    {
        "manager": "syphilis.manager.rdata",
        "tag": "syphilis-manager-v2026.09.09",
        "sha256": "c3e3c983d6b4e9c961f735f9c59d45483bd63cfa715cf75c1fae874da2d129e6",
        "published_at": "2026-09-09T19:22:51Z",
    },
)
# The census made current on 2026-10-08 (jheem_analyses 8d28541f), as an immutable
# census-only release, with the September syphilis manager.
OCTOBER_INPUTS = (
    {
        "manager": "census.manager.rdata",
        "tag": "census-manager-v2026.10.08",
        "sha256": "fc45487d38f87c8692ab0bc615d8f4b049d8da363956d7bf02d733c9aa9dee64",
        "published_at": "2026-10-09T15:45:35Z",
    },
    SEPTEMBER_INPUTS[1],
)
PROFILES = {"retained": INPUTS, "native-2026-10-01": NATIVE_OCTOBER_INPUTS,
            "september-2026": SEPTEMBER_INPUTS, "october-2026": OCTOBER_INPUTS}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def materialize(cache: Path, specification: dict[str, str]) -> None:
    manager = specification["manager"]
    tag = specification["tag"]
    expected = specification["sha256"]
    directory = cache / "data-managers" / manager / tag
    artifact = directory / manager
    metadata = directory / "resolution.json"
    directory.mkdir(parents=True, exist_ok=True)

    if not artifact.exists() or sha256(artifact) != expected:
        url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{manager}"
        request = Request(url, headers={"User-Agent": "jheem-shield-ci"})
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
            temporary_path = Path(temporary.name)
            with urlopen(request, timeout=120) as response:
                shutil.copyfileobj(response, temporary)
        try:
            actual = sha256(temporary_path)
            if actual != expected:
                raise RuntimeError(
                    f"SHA-256 mismatch for {manager}: expected {expected}, got {actual}"
                )
            os.replace(temporary_path, artifact)
        finally:
            temporary_path.unlink(missing_ok=True)

    resolution = {
        "schema_version": 1,
        "manager": manager,
        "repository": REPOSITORY,
        "requested_tag": tag,
        "resolved_tag": tag,
        "asset": manager,
        "sha256": expected,
        "published_at": specification["published_at"],
    }
    metadata.write_text(json.dumps(resolution, indent=2) + "\n")
    print(f"Prepared {manager}@{tag} ({expected})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache_directory", type=Path)
    parser.add_argument("--profile", choices=PROFILES, default="retained")
    parser.add_argument("--github-env", type=Path,
                        help="Append the selected test tags and seed to this workflow environment file")
    args = parser.parse_args()
    cache = args.cache_directory.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    selected = PROFILES[args.profile]
    for specification in selected:
        materialize(cache, specification)
    if args.github_env:
        with args.github_env.open("a") as output:
            output.write(f"CENSUS_TAG={selected[0]['tag']}\n")
            output.write(f"SYPHILIS_TAG={selected[1]['tag']}\n")
            seed = "20260916" if args.profile == "retained" else "0"
            output.write(f"SHIELD_RANDOM_SEED={seed}\n")
    print(f"Prepared profile: {args.profile}")


if __name__ == "__main__":
    main()
