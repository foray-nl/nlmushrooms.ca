import json

import crawl_parity
from conftest import write
from foray_ce import parity

PAGE = """<html><head><title>T</title><meta name="description" content=" d  x ">
<link rel="canonical" href="https://h.test/a/b"><meta property="og:title" content="T">
<meta property="og:url" content="https://h.test/a/b">
<script type="application/ld+json">{"@graph":[{"@type":"WebPage"},{"@type":["Event","Thing"]}]}</script></head>
<body><h1>One</h1><h2>Two</h2><a href="/x">x</a><img src="a" alt="A"><img src="b" alt=""></body></html>"""


def resp(status=200, body="", **headers):
    return {"status": status, "headers": {k.lower(): v for k, v in headers.items()}, "body": body, "sha256": None, "size": 0}


def test_facts_extracts_comparable_fields():
    f = parity.facts(PAGE)
    assert f["title"] == "T" and f["description"] == "d x" and f["canonical_path"] == "/a/b"
    assert f["ld_types"] == ["Event", "Thing", "WebPage"]
    assert f["headings"] == [("h1", "One"), ("h2", "Two")] and f["links"] == 1
    assert (f["images"], f["images_with_alt"]) == (2, 1)


def test_compare_pages_reports_only_differences():
    a = parity.facts(PAGE)
    b = parity.facts(PAGE.replace("<title>T", "<title>U"))
    assert [d["field"] for d in parity.compare_pages(a, b)] == ["title"]
    assert parity.compare_pages(a, a) == []


def entry(**kw):
    base = {"from": "/a.html", "to": "/en/a", "status": 301, "kind": "page", "source": "a.html"}
    return dict(base, **kw)


def test_check_entry_ok_one_hop():
    seen = {"https://n.test/a.html": resp(301, location="https://n.test/en/a"), "https://n.test/en/a": resp(200, PAGE)}
    old = lambda f: resp(200, PAGE)  # noqa: E731
    result = parity.check_entry(entry(), "https://o.test", "https://n.test", seen.__getitem__, old)
    assert result["ok"], result


def test_check_entry_flags_wrong_location_second_hop_and_diff():
    fetch = {"https://n.test/a.html": resp(301, location="/en/other"), "https://n.test/en/a": resp(301)}
    r = parity.check_entry(entry(), None, "https://n.test", fetch.__getitem__)
    assert not r["ok"] and any("Location" in p for p in r["problems"]) and any("second hop" in p for p in r["problems"])
    fetch = {"https://n.test/a.html": resp(301, location="/en/a"), "https://n.test/en/a": resp(200, PAGE.replace("<title>T", "<title>U"))}
    r = parity.check_entry(entry(), "https://o.test", "https://n.test", fetch.__getitem__, lambda f: resp(200, PAGE))
    assert r["problems"] == ["title differs"]


def test_forced_404_and_failed_request():
    e = entry(status=404, to=None, kind="archive", **{"from": "/archive/x"})
    assert parity.check_entry(e, None, "https://n.test", lambda u: resp(404))["ok"]
    assert not parity.check_entry(e, None, "https://n.test", lambda u: resp(200))["ok"]
    bad = parity.check_entry(e, None, "https://n.test", lambda u: {"status": 0, "headers": {}, "error": "timeout"})
    assert "request failed" in bad["problems"][0]


def test_upload_checksum_mismatch():
    e = entry(kind="upload", to="/f/x", source="x.pdf")
    fetch = {"https://n.test/a.html": resp(301, location="/f/x"), "https://n.test/f/x": dict(resp(200), sha256="bad")}
    assert "checksum" in parity.check_entry(e, None, "https://n.test", fetch.__getitem__, None, "good")["problems"][0]


def test_cli_dry_run_sends_nothing(site_root, capsys):
    write(site_root, "netlify.toml", "")
    boom = lambda url: (_ for _ in ()).throw(AssertionError("network used"))  # noqa: E731
    assert crawl_parity.main(["--root", site_root, "--new", "https://n.test", "--dry-run"], fetcher=boom) == 0
    assert json.loads(capsys.readouterr().out)["planned_requests"] > 0


def test_cli_run_with_fake_fetcher_reports_failures(site_root, tmp_path, capsys):
    write(site_root, "netlify.toml", "")
    out = tmp_path / "p.json"
    code = crawl_parity.main(["--root", site_root, "--new", "https://n.test", "--kinds", "page", "--delay", "0",
                              "--out", str(out)], fetcher=lambda url: resp(404))
    assert code == 1 and json.loads(out.read_text())["failed"] > 0


def test_real_fetcher_against_local_server_does_not_follow_redirects():
    import http.server
    import threading

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/r":
                self.send_response(301)
                self.send_header("Location", "/p")
                self.end_headers()
            else:
                body = b"<html><title>Hi</title></html>"
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    try:
        fetch = parity.Fetcher(timeout=5)
        r = fetch(base + "/r")
        assert r["status"] == 301 and r["headers"]["location"] == "/p"
        assert "Hi" in fetch(base + "/p")["body"]
        assert fetch("http://127.0.0.1:1/")["status"] == 0
    finally:
        server.shutdown()
