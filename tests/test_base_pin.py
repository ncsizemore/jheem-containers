"""Base-image provenance validator (structural, fast — runs on every PR).

The cache-poisoning incident showed that validating *behavior* (golden reproduction,
which is base-agnostic) never proves a model is on the *right* base. The
`test_version_provenance` base check helps, but it reads `JHEEM_BASE_VERSION`
(set from `ARG BASE_VERSION`), which can drift from the actual `FROM` digest.

These checks close that gap by validating the digest chain directly:
  1. every model's base `FROM` is digest-pinned (not a mutable tag);
  2. the pinned digest equals the digest the registry currently serves for the
     claimed `jheem-base:<ARG BASE_VERSION>` tag — catches ARG/digest drift AND a
     base tag re-pushed under us;
  3. `test_config.json`'s base_version agrees with the Dockerfile ARG.

No simulation; just file parsing + one registry query per model. The real cure is
Phase B (pass the freshly-built base digest into model builds); this is the interim
guard until then.
"""
import re
import subprocess

import pytest

from conftest import REPO, config

MODELS = list(config().keys())

_ARG = re.compile(r"ARG BASE_VERSION=(\S+)")
_FROM = re.compile(
    r"FROM ghcr\.io/ncsizemore/jheem-base:\$\{BASE_VERSION\}(@sha256:[a-f0-9]{64})?")


def _base_ref(name):
    """(version, digest_or_None) parsed from the model's base FROM line."""
    text = (REPO / "models" / name / "Dockerfile").read_text()
    arg = _ARG.search(text)
    frm = _FROM.search(text)
    digest = frm.group(1)[1:] if (frm and frm.group(1)) else None  # strip leading '@'
    return (arg.group(1) if arg else None), digest


def _registry_index_digest(ref):
    out = subprocess.run(
        ["docker", "buildx", "imagetools", "inspect", ref],
        capture_output=True, text=True, check=True, timeout=120).stdout
    for line in out.splitlines():
        if line.startswith("Digest:"):
            return line.split()[1]
    raise AssertionError(f"no top-level Digest in imagetools inspect of {ref}")


@pytest.mark.parametrize("name", MODELS)
def test_base_is_digest_pinned(name):
    version, digest = _base_ref(name)
    assert version, f"{name}: no `ARG BASE_VERSION` found"
    assert digest, (f"{name}: base FROM is a mutable tag, not digest-pinned — this is "
                    f"exactly what let the gha cache serve stale base layers")


@pytest.mark.parametrize("name", MODELS)
def test_base_digest_matches_registry(name):
    version, digest = _base_ref(name)
    registry = _registry_index_digest(f"ghcr.io/ncsizemore/jheem-base:{version}")
    assert digest == registry, (
        f"{name}: pinned base digest != registry digest for jheem-base:{version}\n"
        f"  pinned:   {digest}\n  registry: {registry}\n"
        f"  => ARG/digest drift (ARG bumped, digest not), or the base tag was re-pushed")


@pytest.mark.parametrize("name", MODELS)
def test_config_base_version_matches_dockerfile(name):
    version, _ = _base_ref(name)
    cfg = config()[name].get("base_version")
    assert cfg == version, \
        f"{name}: test_config base_version '{cfg}' != Dockerfile ARG BASE_VERSION '{version}'"
