import json
import os

import pytest
import yaml

import seed_packet
from foray_ce import inventory, packet, site
from conftest import write


@pytest.fixture
def built(site_root):
    write(site_root, "netlify.toml", '[[redirects]]\n from = "/page40.html"\n to = "/omphalina_2021.html"\n status = 301\n')
    s = site.Site(site_root)
    uploads = inventory.build(s)
    files, blobs, gaps = packet.build(s, uploads)
    return s, uploads, files, blobs, gaps


def by_key(recs):
    return {r["key"]: r for r in recs}


def records(files, name):
    return files[f"records/{name}.yml"][1]


def test_pages_nest_with_refs_and_bodies(built):
    files = built[2]
    pages = by_key(records(files, "pages"))
    page = pages["past-forays/foray-2025"]
    assert page["refs"]["parent"] == "page:past-forays"
    assert page["refs"]["share_image"] == "upload:f25"
    assert page["translations"]["en"]["title"] == "Foray 2025"
    assert page["attributes"]["seo_title"] == "Foray 2025 | Past Forays | Foray Test"
    blocks = by_key(records(files, "content_blocks"))
    assert "<h1>foray_2025</h1>" in blocks["past-forays/foray-2025.body"]["translations"]["en"]["content_html"]
    assert "home" in pages and files["records/pages.yml"][0] == "page"


def test_seo_title_nests_nearest_first(built):
    s = built[0]
    assert packet.seo_title(s, "foray_2025.html") == "Foray 2025 | Past Forays | Foray Test"
    assert packet.seo_title(s, "index.html") == "Foray Test"


def test_gaps_logged_against_deficiency_numbers(built):
    gaps = {g["id"]: g for g in built[4].as_list()}
    assert gaps["html-block-tag-table"]["deficiency"] == 2
    assert gaps["social-flickr"]["deficiency"] == 2 and gaps["legacy-links-in-content"]["count"] == 1
    assert gaps["blob-total"]["deficiency"] == 3 and gaps["platform-target"]["deficiency"] == 6


def test_events_and_issue_refs(built):
    files = built[2]
    events = by_key(records(files, "events"))
    assert events["foray-2025"]["refs"]["report"] == "upload:foray-report-2025"
    assert events["foray-2021"]["attributes"]["status"] == "cancelled"
    issue = by_key(records(files, "omphalina_issues"))["volume-12/issue-3"]
    assert issue["refs"]["pdf"] == "upload:omphalina-xii-3" and issue["refs"]["cover"].startswith("upload:")


def test_all_refs_resolve_inside_the_packet(built):
    files = built[2]
    keys = {(rtype, r["key"]) for rtype, recs in files.values() for r in recs}
    for _t, recs in files.values():
        for rec in recs:
            for value in (rec.get("refs") or {}).values():
                assert tuple(value.split(":", 1)) in keys, (rec["key"], value)


def test_keys_follow_the_spec_pattern_and_records_hold_only_spec_fields(built):
    import re
    allowed = {"key", "attributes", "translations", "refs", "files", "position"}
    for _t, recs in built[2].values():
        for rec in recs:
            assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,254}", rec["key"]), rec["key"]
            assert set(rec) <= allowed


def test_extract_body_nested_divs_and_home():
    html = '<main><div class="page-body"><div><p>a</p></div><p>b</p></div></main>'
    assert packet.extract_body(html) == "<div><p>a</p></div><p>b</p>"
    home = '<main class="home"><!-- layout:breadcrumb --><nav></nav><!-- /layout:breadcrumb --><h1>x</h1></main>'
    assert packet.extract_body(home) == "<h1>x</h1>"


def test_manifest_lists_every_file_and_blob(built, site_root):
    s, _u, files, blobs, _g = built
    text, man = packet.render(s, files, blobs, site_root)
    paths = {e["path"] for e in man["files"]}
    assert {"packet.yml", "records/pages.yml"} <= paths
    assert sum(p.startswith("blobs/") for p in paths) == len(blobs)
    env = yaml.safe_load(text["packet.yml"])["better_together"]
    assert env["version"] == "2.0" and env["packet"]["mode"] == "add_only" and "target" not in env["packet"]
    assert env["packet"]["records"] == sorted(files)


def test_cli_dry_run_writes_nothing(site_root, tmp_path, capsys):
    write(site_root, "netlify.toml", "")
    out = tmp_path / "pk"
    assert seed_packet.main(["--root", site_root, "--out", str(out), "--dry-run"]) == 0
    assert not out.exists()
    assert json.loads(capsys.readouterr().out)["blobs"] == 9


def test_cli_writes_packet_with_hardlinked_blobs(site_root, tmp_path):
    write(site_root, "netlify.toml", "")
    out = tmp_path / "pk"
    assert seed_packet.main(["--root", site_root, "--out", str(out)]) == 0
    man = json.loads((out / "MANIFEST.json").read_text())
    blob = next(e for e in man["files"] if e["path"].startswith("blobs/"))
    assert (out / blob["path"]).stat().st_size == blob["size"]
    assert (out / "gaps.json").exists()
    again = tmp_path / "pk2"
    assert seed_packet.main(["--root", site_root, "--out", str(again), "--blobs", "none"]) == 0
    assert not (again / "blobs").exists()


def test_pointer_files_fail_with_exit_3(site_root, tmp_path):
    write(site_root, "netlify.toml", "")
    with open(site_root + "/anncum_1.pdf", "wb") as handle:
        handle.write(b"version https://git-lfs.github.com/spec/v1\noid sha256:aa\nsize 9\n")
    assert seed_packet.main(["--root", site_root, "--dry-run"]) == 3
    assert seed_packet.main(["--root", site_root, "--dry-run", "--allow-pointers"]) == 0


def test_out_inside_repo_must_be_tmp(site_root):
    write(site_root, "netlify.toml", "")
    with pytest.raises(SystemExit):
        seed_packet.main(["--root", site_root, "--out", os.path.join(site_root, "images", "pk")])
    assert seed_packet.main(["--root", site_root, "--out", os.path.join(site_root, "tmp", "pk"), "--blobs", "none"]) == 0


def test_output_validates_against_cc_schemas_when_available(built, site_root):
    """Set SEED_SCHEMA_DIR to the CE config/seeds/schema directory to check against the real JSON Schemas."""
    jsonschema = pytest.importorskip("jsonschema")
    schema_dir = os.environ.get("SEED_SCHEMA_DIR")
    if not schema_dir or not os.path.isdir(schema_dir):
        pytest.skip("SEED_SCHEMA_DIR not set")
    load = lambda n: json.load(open(os.path.join(schema_dir, f"{n}.schema.json")))  # noqa: E731
    s, _u, files, blobs, _g = built
    text, man = packet.render(s, files, blobs, site_root)
    jsonschema.validate(yaml.safe_load(text["packet.yml"])["better_together"], load("envelope"))
    jsonschema.validate(man, load("manifest"))
    for rel in files:
        jsonschema.validate(yaml.safe_load(text[rel]), load("records"))
