import pytest

import redirect_map
from conftest import write
from foray_ce import inventory, redirects, site

NETLIFY = """
[[redirects]]
  from = "/page40.html"
  to = "/omphalina_2021.html"
  status = 301
[[redirects]]
  from = "/archive/*"
  to = "/404.html"
  status = 404
  force = true
"""


@pytest.fixture
def s(site_root):
    write(site_root, "netlify.toml", NETLIFY)
    return site.Site(site_root)


def build(s, **kw):
    return redirects.build(s, inventory.build(s, hash_files=False), **kw)


def test_pages_and_extensionless_forms(s):
    by = {e["from"]: e for e in build(s)}
    assert by["/foray_2025.html"]["to"] == "/en/past-forays/foray-2025"
    assert by["/foray_2025"]["to"] == "/en/past-forays/foray-2025"
    assert by["/index.html"]["to"] == "/en" and "/" not in by


def test_netlify_rules_are_one_hop_and_404s_kept(s):
    by = {e["from"]: e for e in build(s)}
    assert by["/page40.html"]["to"] == "/en/omphalina/omphalina-2021"
    assert by["/archive/*"]["status"] == 404 and by["/archive/*"]["to"] is None


def test_pdf_paths_include_encoded_forms(s):
    by = {e["from"]: e for e in build(s)}
    assert by["/omphaline/Omphalina XII-1.pdf"]["to"] == "/f/omphalina-xii-1"
    assert by["/omphaline/Omphalina%20XII-1.pdf"]["to"] == "/f/omphalina-xii-1"
    assert "/archive/forms/old.pdf" not in by and "/images/poster.png" not in by


def test_no_locale_prefix_and_images_option(s):
    by = {e["from"]: e for e in build(s, prefix="", include_images=True)}
    assert by["/index.html"]["to"] == "/"
    assert "/images/poster.png" in by


def test_chain_is_rejected(s):
    with pytest.raises(redirects.RedirectError, match="chain"):
        redirects.validate([{"from": "/a", "to": "/b", "status": 301}, {"from": "/b", "to": "/c", "status": 301}])


def test_conflict_is_rejected():
    with pytest.raises(redirects.RedirectError, match="conflicting"):
        redirects.validate([{"from": "/a", "to": "/b", "status": 301}, {"from": "/a", "to": "/c", "status": 301}])


def test_netlify_rule_to_unknown_page_fails(s):
    write(s.root, "netlify.toml", '[[redirects]]\n from = "/x"\n to = "/nope.html"\n status = 301\n')
    with pytest.raises(redirects.RedirectError, match="not a registered page"):
        build(s)


def test_cli_dry_run_writes_nothing_and_out_writes(s, tmp_path, capsys):
    out = tmp_path / "o" / "r.yml"
    assert redirect_map.main(["--root", s.root, "--out", str(out), "--dry-run"]) == 0
    assert not out.exists()
    assert redirect_map.main(["--root", s.root, "--out", str(out)]) == 0
    assert "redirect:/foray_2025.html" in out.read_text()
    for fmt in ("json", "csv"):
        assert redirect_map.render(build(s), fmt).strip()


def test_netlify_parser_ignores_headers_tables(s):
    write(s.root, "netlify.toml", NETLIFY + '\n[[headers]]\n  for = "/*.html"\n  [headers.values]\n    Cache-Control = "x"\n')
    rules = redirects.netlify_rules(s.root)
    assert [r["from"] for r in rules] == ["/page40.html", "/archive/*"] and rules[0]["status"] == 301
