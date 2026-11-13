"""Crawl parity: every old URL on the old site versus the new CE site (read-only HTTP, bounded)."""
import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

USER_AGENT = "foray-ce-parity/1.0 (read-only migration check)"
MAX_HTML = 5 * 1024 * 1024


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Fetcher:
    """GET without following redirects. Returns dict(status, headers, body, sha256, size); body only for HTML."""

    def __init__(self, timeout=15, max_bytes=MAX_HTML, hash_bodies=False):
        self.timeout, self.max_bytes, self.hash_bodies = timeout, max_bytes, hash_bodies
        self.opener = urllib.request.build_opener(_NoRedirect)

    def __call__(self, url):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
        try:
            response = self.opener.open(request, timeout=self.timeout)
        except urllib.error.HTTPError as err:
            response = err
        except (urllib.error.URLError, TimeoutError, OSError) as err:
            return {"status": 0, "headers": {}, "body": "", "error": str(err), "sha256": None, "size": 0}
        headers = {k.lower(): v for k, v in response.headers.items()}
        is_html = "text/html" in headers.get("content-type", "")
        digest, size, chunks = hashlib.sha256(), 0, []
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            size += len(chunk)
            if is_html and size <= self.max_bytes:
                chunks.append(chunk)
            if self.hash_bodies and not is_html:
                digest.update(chunk)
            elif not is_html:
                break
        body = b"".join(chunks).decode("utf-8", "replace") if is_html else ""
        return {"status": response.status if hasattr(response, "status") else response.code, "headers": headers,
                "body": body, "sha256": digest.hexdigest() if self.hash_bodies and not is_html else None,
                "size": size}


class _Facts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.meta, self.canonical, self.ld, self.headings = {}, None, [], []
        self.links = self.images = self.images_with_alt = 0
        self._in = None
        self._buf = ""

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self._in, self._buf = "title", ""
        elif tag in ("h1", "h2", "h3"):
            self._in, self._buf = tag, ""
        elif tag == "script" and a.get("type") == "application/ld+json":
            self._in, self._buf = "ld", ""
        elif tag == "meta":
            name = a.get("name") or a.get("property")
            if name:
                self.meta[name] = " ".join((a.get("content") or "").split())
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = a.get("href")
        elif tag == "a" and a.get("href"):
            self.links += 1
        elif tag == "img":
            self.images += 1
            self.images_with_alt += 1 if (a.get("alt") or "").strip() else 0

    def handle_data(self, data):
        if self._in:
            self._buf += data

    def handle_endtag(self, tag):
        if self._in == "title" and tag == "title":
            self.title = " ".join(self._buf.split())
        elif self._in == "ld" and tag == "script":
            self.ld.append(self._buf)
        elif self._in == tag and tag in ("h1", "h2", "h3"):
            self.headings.append((tag, " ".join(self._buf.split())))
        else:
            return
        self._in = None


def ld_types(blobs):
    types = []
    for raw in blobs:
        try:
            data = json.loads(raw)
        except ValueError:
            types.append("INVALID")
            continue
        for node in data if isinstance(data, list) else data.get("@graph", [data]):
            kind = node.get("@type") if isinstance(node, dict) else None
            types.extend(kind if isinstance(kind, list) else [kind or "?"])
    return sorted(types)


def facts(html, base_host=None):
    parser = _Facts()
    parser.feed(html)
    path = lambda url: urllib.parse.urlparse(url).path if url else None  # noqa: E731
    og = {k: v for k, v in parser.meta.items() if k.startswith("og:") and k not in ("og:url", "og:image")}
    return {"title": parser.title, "description": parser.meta.get("description"), "canonical_path": path(parser.canonical),
            "og": og, "og_url_path": path(parser.meta.get("og:url")), "ld_types": ld_types(parser.ld),
            "headings": parser.headings, "links": parser.links, "images": parser.images,
            "images_with_alt": parser.images_with_alt, "robots": parser.meta.get("robots")}


def compare_pages(old, new):
    """List of {field, old, new} differences for fields that must match after the migration."""
    diffs = []
    for field in ("title", "description", "ld_types", "headings", "links", "images", "images_with_alt", "og"):
        if old[field] != new[field]:
            diffs.append({"field": field, "old": old[field], "new": new[field]})
    if not new["canonical_path"]:
        diffs.append({"field": "canonical_path", "old": old["canonical_path"], "new": None})
    return diffs


def check_entry(entry, old_base, new_base, fetch, old_cache=None, local_sha=None, compare=True):
    """Check one redirect-map entry. Returns a result dict with `ok` and a list of `problems`."""
    problems = []
    first = fetch(new_base + entry["from"].replace(" ", "%20"))
    result = {"from": entry["from"], "expected": entry["to"], "status": first["status"], "problems": problems}
    if first["status"] == 0:
        problems.append("request failed: " + first.get("error", ""))
    elif entry["status"] == 404:
        if first["status"] != 404:
            problems.append(f"expected 404, got {first['status']}")
    elif first["status"] != entry["status"]:
        problems.append(f"expected {entry['status']}, got {first['status']}")
    else:
        location = urllib.parse.urlparse(first["headers"].get("location", "")).path
        result["location"] = location
        if urllib.parse.unquote(location) != entry["to"]:
            problems.append(f"expected Location {entry['to']}, got {location}")
        final = fetch(new_base + entry["to"])
        result["final_status"] = final["status"]
        if final["status"] != 200:
            problems.append(f"destination returned {final['status']} (a second hop or an error)")
        elif entry["kind"] == "upload" and local_sha and final.get("sha256") and final["sha256"] != local_sha:
            problems.append("PDF checksum differs from the source file")
        elif entry["kind"] == "page" and compare and old_base:
            old = old_cache(entry["source"]) if old_cache else None
            if old and old["status"] == 200:
                problems.extend(f"{d['field']} differs" for d in compare_pages(facts(old["body"]), facts(final["body"])))
    result["ok"] = not problems
    return result


def plan(entries, old_base, new_base, kinds=None, limit=None):
    chosen = [e for e in entries if not kinds or e["kind"] in kinds]
    return chosen[:limit] if limit else chosen
