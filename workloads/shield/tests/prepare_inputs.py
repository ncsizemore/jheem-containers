#!/usr/bin/env python3
"""Materialize the small, immutable input set used by SHIELD CI.

This is test infrastructure, not a runtime downloader. Recorded containers mount
the resulting cache read-only and run without network access.
"""

from __future__ import annotations

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
        "tag": "syphilis-manager-v2026.03.26",
        "sha256": "9e91257253c459e91ef11640c1002a7ae03d61fe7e832510bac8656f1bdf3b92",
        "published_at": "2026-03-26T16:35:30Z",
    },
)


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
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} CACHE_DIRECTORY")
    cache = Path(sys.argv[1]).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    for specification in INPUTS:
        materialize(cache, specification)


if __name__ == "__main__":
    main()
