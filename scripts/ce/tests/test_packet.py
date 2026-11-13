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


def test_pages_nest_with_refs_and_bodies(built):
    _s, _u, files, _b, _g = built
    pages = by_key(files["records/pages.yml"])
    page = pages["page:past-forays/foray-2025"]
    assert page["refs"]["parent"] == {"ref": {"type": "page", "key": "page:past-forays"}}
    assert page["refs"]["share_image"]["ref"]["key"] == "upload:f25"
    assert page["translations"]["title"]["en"] == "Foray 2025"
    assert page["attributes"]["seo_title"] == "Foray 2025 | Past Forays | Foray Test"
    assert "<h1>foray_2025</h1>" in pages["block:past-forays/foray-2025:body"]["translations"]["content_html"]["en"]
    assert "page:home" in pages


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
    events = by_key(files["records/events.yml"])
    assert events["event:foray-2025"]["refs"]["report"]["ref"]["key"] == "upload:foray-report-2025"
    assert events["event:foray-2021"]["attributes"]["status"] == "cancelled"
    issue = by_key(files["records/omphalina.yml"])["omphalina:volume-12:issue-3"]
    assert issue["refs"]["pdf"]["ref"]["key"] == "upload:omphalina-xii-3"
    assert issue["refs"]["cover"]["ref"]["type"] == "upload"


def test_all_refs_resolve_inside_the_packet(built):
    files = built[2]
    keys = {(r["type"], r["key"]) for recs in files.values() for r in recs}
    for recs in files.values():
        for rec in recs:
            for value in (rec.get("refs") or {}).values():
                assert (value["ref"]["type"], value["ref"]["key"]) in keys, (rec["key"], value)


def test_fingerprints_are_stable_and_content_sensitive(built):
    rec = built[2]["records/uploads.yml"][0]
    assert packet.fingerprint(rec) == rec["fingerprint"]
    changed = dict(rec, attributes=dict(rec["attributes"], title="other"))
    assert packet.fingerprint(changed) != rec["fingerprint"]


def test_extract_body_nested_divs_and_home():
    html = '<main><div class="page-body"><div><p>a</p></div><p>b</p></div></main>'
    assert packet.extract_body(html) == "<div><p>a</p></div><p>b</p>"
    home = '<main class="home"><!-- layout:breadcrumb --><nav></nav><!-- /layout:breadcrumb --><h1>x</h1></main>'
    assert packet.extract_body(home) == "<h1>x</h1>"


def test_manifest_lists_every_file_and_blob(built, site_root):
    s, _u, files, blobs, _g = built
    text, man = packet.render(s, files, blobs, site_root)
    paths = {e["path"] for e in man["files"]}
    assert "records/pages.yml" in paths
    assert sum(p.startswith("blobs/") for p in paths) == len(blobs)
    env = yaml.safe_load(text["packet.yml"])["better_together"]
    assert env["version"] == "2.0" and env["seed"]["payload"]["target"]["platform"] == "required"


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
