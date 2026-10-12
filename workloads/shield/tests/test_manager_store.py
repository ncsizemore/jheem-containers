import hashlib
import importlib.util
import io
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manager_store", ROOT / "manager_store.py")
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)

SYPHILIS, TAG = "syphilis.manager.rdata", "syphilis-manager-v2026.10.09"
CONTENT = b"synthetic syphilis manager"
SHA = hashlib.sha256(CONTENT).hexdigest()


def bundled_release(root, manager=SYPHILIS, tag=TAG, content=CONTENT):
    directory = root / "data-managers" / manager / tag
    directory.mkdir(parents=True)
    (directory / manager).write_bytes(content)
    (directory / "resolution.json").write_text(json.dumps({
        "repository": store.REPOSITORY, "manager": manager, "resolved_tag": tag,
        "sha256": hashlib.sha256(content).hexdigest()}))
    return root


def fake_github(monkeypatch, published=SHA, content=CONTENT, calls=None):
    def urlopen(request, timeout):
        url = request.full_url
        if calls is not None:
            calls.append(url)
        if url.endswith("/releases/tags/" + TAG):
            return io.BytesIO(json.dumps({"published_at": "2026-10-09T16:41:02Z", "assets": [
                {"name": SYPHILIS, "digest": "sha256:" + published,
                 "browser_download_url": "https://example.invalid/" + SYPHILIS}]}).encode())
        return io.BytesIO(content)
    monkeypatch.setattr(store, "urlopen", urlopen)


def test_bundled_release_is_copied_without_network(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "urlopen", lambda *a, **k: pytest.fail("no network expected"))
    target = store.ensure(tmp_path / "store", SYPHILIS, TAG, bundled_release(tmp_path / "bundle"))
    assert target == tmp_path / "store" / SYPHILIS / TAG
    assert (target / SYPHILIS).read_bytes() == CONTENT
    assert store.check(target, SYPHILIS, TAG) == SHA
    # A second launch reuses the stored copy.
    assert store.ensure(tmp_path / "store", SYPHILIS, TAG) == target


def test_missing_release_is_downloaded_and_checked_against_the_published_digest(tmp_path, monkeypatch):
    calls = []
    fake_github(monkeypatch, calls=calls)
    target = store.ensure(tmp_path / "store", SYPHILIS, TAG, tmp_path / "empty-bundle")
    resolution = json.loads((target / "resolution.json").read_text())
    assert resolution["sha256"] == SHA and resolution["resolved_tag"] == TAG
    assert resolution["repository"] == "tfojo1/jheem_analyses"
    assert len(calls) == 2
    store.ensure(tmp_path / "store", SYPHILIS, TAG)
    assert len(calls) == 2


def test_download_that_does_not_match_the_published_digest_stores_nothing(tmp_path, monkeypatch):
    fake_github(monkeypatch, published="0" * 64)
    with pytest.raises(ValueError, match="published digest"):
        store.ensure(tmp_path / "store", SYPHILIS, TAG)
    assert list((tmp_path / "store" / SYPHILIS).iterdir()) == []


def test_release_without_a_published_digest_is_refused(tmp_path, monkeypatch):
    fake_github(monkeypatch, published="")
    with pytest.raises(ValueError, match="SHA-256 digest"):
        store.ensure(tmp_path / "store", SYPHILIS, TAG)


@pytest.mark.parametrize("damage", ["artifact", "record"])
def test_a_changed_stored_release_stops_the_launch_and_is_not_replaced(tmp_path, monkeypatch, damage):
    target = store.ensure(tmp_path / "store", SYPHILIS, TAG, bundled_release(tmp_path / "bundle"))
    monkeypatch.setattr(store, "urlopen", lambda *a, **k: pytest.fail("no network expected"))
    path = target / (SYPHILIS if damage == "artifact" else "resolution.json")
    path.chmod(0o644)
    path.write_bytes(b"changed" if damage == "artifact" else b'{"sha256": "x"}')
    with pytest.raises(ValueError):
        store.ensure(tmp_path / "store", SYPHILIS, TAG, tmp_path / "bundle")
    assert path.read_bytes() in (b"changed", b'{"sha256": "x"}')


def test_a_damaged_bundled_copy_is_not_stored(tmp_path):
    bundle = bundled_release(tmp_path / "bundle")
    (bundle / "data-managers" / SYPHILIS / TAG / SYPHILIS).write_bytes(b"damaged")
    with pytest.raises(ValueError, match="SHA-256"):
        store.ensure(tmp_path / "store", SYPHILIS, TAG, bundle)
    assert not (tmp_path / "store" / SYPHILIS / TAG).exists()


def test_a_concurrent_writer_wins_and_its_copy_is_used(tmp_path, monkeypatch):
    other = bundled_release(tmp_path / "other")
    original = store.os.rename

    def rename(source, destination):
        # Another launch publishes the same release just before this one.
        original(other / "data-managers" / SYPHILIS / TAG, destination)
        return original(source, destination)
    monkeypatch.setattr(store.os, "rename", rename)
    target = store.ensure(tmp_path / "store", SYPHILIS, TAG, bundled_release(tmp_path / "bundle"))
    assert store.check(target, SYPHILIS, TAG) == SHA
    assert [p.name for p in (tmp_path / "store" / SYPHILIS).iterdir()] == [TAG]


@pytest.mark.parametrize("manager,tag", [(SYPHILIS, "syphilis-manager-latest"),
                                         (SYPHILIS, "census-manager-v2026.10.08"),
                                         ("census.manager.rdata", "census-manager-latest"),
                                         ("other.rdata", "other-v2026.01.01"),
                                         (SYPHILIS, "../syphilis-manager-v2026.10.09")])
def test_only_immutable_releases_of_known_managers(tmp_path, manager, tag):
    with pytest.raises(ValueError):
        store.ensure(tmp_path / "store", manager, tag)
    assert not (tmp_path / "store").exists()


def test_census_release_names(tmp_path):
    for tag in ("census-manager-v2026.10.08", "data-managers-v2026.08.26"):
        store.validate("census.manager.rdata", tag)
