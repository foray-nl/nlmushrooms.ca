"""Seed packet (protocol 2.0 draft layout) for the foray site.

packet.yml, MANIFEST.json, records/*.yml and blobs/<sha256>. Every place where the protocol or the CE models
cannot carry the data is recorded in the gap log against the numbered deficiency list.
"""
import hashlib
import json
import os
import re
import subprocess

import yaml

from . import redirects as redirectlib
from . import site as sitelib

PACKET_ID = "foray-nl-site"
TAG_NEEDS_A5 = ("table", "thead", "tbody", "tr", "td", "th", "details", "summary", "section")
ATTR_NEEDS_A5 = ("id", "role", "scope", "colspan")
VOID = {"br", "hr", "img", "input", "meta", "link", "source", "wbr", "area", "col"}
TAG = re.compile(r"<(/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*?(/?)>")


class Gaps:
    """Collects gaps keyed by (deficiency number, id); repeated hits only raise the count."""

    def __init__(self):
        self.items = {}

    def add(self, deficiency, gap_id, message, count=1):
        key = (deficiency, gap_id)
        if key in self.items:
            self.items[key]["count"] += count
        else:
            self.items[key] = {"deficiency": deficiency, "id": gap_id, "message": message, "count": count}

    def as_list(self):
        return [self.items[k] for k in sorted(self.items)]


def fingerprint(record):
    body = {k: record.get(k) for k in ("type", "key", "attributes", "translations", "refs", "files")}
    return hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()[:16]


def ref(rtype, key):
    return {"ref": {"type": rtype, "key": key}}


def record(rtype, key, attributes, translations=None, refs=None, files=None):
    out = {"type": rtype, "key": key, "attributes": attributes}
    if translations:
        out["translations"] = translations
    if refs:
        out["refs"] = refs
    if files:
        out["files"] = files
    out["fingerprint"] = fingerprint(out)
    return out


def extract_body(html):
    """Inner HTML of div.page-body, or of <main> minus its breadcrumb nav (the home page has no page-body)."""
    start = re.search(r'<div class="page-body">', html)
    if start:
        return _inner(html, start.end(), "div")
    main = re.search(r"<main\b[^>]*>", html)
    if not main:
        return None
    inner = _inner(html, main.end(), "main")
    return re.sub(r"<!-- layout:breadcrumb -->.*?<!-- /layout:breadcrumb -->", "", inner, flags=re.S).strip()


def _inner(html, pos, tag):
    depth = 1
    for match in TAG.finditer(html, pos):
        name = match.group(2).lower()
        if name != tag or match.group(3):
            continue
        depth += -1 if match.group(1) else 1
        if depth == 0:
            return html[pos:match.start()].strip()
    return html[pos:].strip()


def audit_body(html, page, gaps):
    tags = {m.group(2).lower() for m in TAG.finditer(html)}
    for name in sorted(tags & set(TAG_NEEDS_A5)):
        gaps.add(2, "html-block-tag-" + name, f"Html block sanitizer rejects <{name}> (work item A5); used by {page}")
    for attr in ATTR_NEEDS_A5:
        if re.search(rf"<[a-zA-Z][^>]*\s{attr}=", html):
            gaps.add(2, "html-block-attr-" + attr, f"Html block sanitizer drops the {attr} attribute (A5); used by {page}")
    links = re.findall(r'href="([^"#:]+?)"', html)
    legacy = [h for h in links if h.endswith(".html") or h.lower().endswith((".pdf", ".xlsx"))]
    if legacy:
        gaps.add(4, "legacy-links-in-content", "Body links point at old .html/.pdf paths; the redirect map serves them "
                 "until the interactive link walk rewrites them", len(legacy))
    imgs = len(re.findall(r"<img\b", html))
    if imgs:
        gaps.add(4, "inline-images-need-upload-refs", "Inline <img> src values are old paths; protocol has no "
                 "in-body file reference syntax", imgs)


def build_uploads(uploads, gaps):
    recs, blobs = [], {}
    for item in uploads:
        if item["status"] != "ok":
            gaps.add(3, "blob-" + item["status"], "File has no real bytes (git lfs pull or locate it)")
            continue
        attrs = {"slug": item["slug"], "title": item["title"], "privacy": "public", "source_path": item["path"],
                 "kind": item["kind"]}
        if item["alt"]:
            attrs["alt_text"] = item["alt"]
            gaps.add(2, "upload-alt-text", "Upload has no confirmed alt text field; carried as alt_text", 1)
        files = [{"attachment": "file", "blob": item["sha256"], "filename": item["filename"],
                  "content_type": item["content_type"], "checksum": item["sha256"], "size": item["size"]}]
        recs.append(record("upload", f"upload:{item['slug']}", attrs, files=files))
        blobs.setdefault(item["sha256"], {"source": item["path"], "size": item["size"], "owners": [],
                                          "media_type": item["content_type"]})["owners"].append(f"upload:{item['slug']}")
    big = [u for u in uploads if u["size"] > 10 * 1024 * 1024]
    gaps.add(3, "blob-total", f"{sum(u['size'] for u in uploads)} bytes in {len(blobs)} blobs; the 10 MB cap covers the "
             "YAML only, so blobs need streaming reads and per-blob size policy", len(blobs))
    if big:
        gaps.add(3, "blob-over-10mb", "Blobs over 10 MB (largest need streaming)", len(big))
    ods = [u for u in uploads if u["kind"] == "spreadsheet"]
    if ods:
        gaps.add(2, "spreadsheet-upload", "Confirm Upload accepts .xlsx (species_lists/Omphalina contents.xlsx)", len(ods))
    return recs, blobs


def build_pages(site, uploads_by_path, gaps):
    pages, order = [], {}
    for index, (file, page) in enumerate(site.pages.items()):
        parent = page.get("parent")
        order[parent] = order.get(parent, 0) + 1
        path = site.path(file)
        key = "page:" + (path or "home")
        refs = {}
        if parent:
            refs["parent"] = ref("page", "page:" + (site.path(parent) or "home"))
        if page.get("image"):
            up = uploads_by_path.get(page["image"])
            if up:
                refs["share_image"] = ref("upload", f"upload:{up['slug']}")
            gaps.add(2, "page-share-image", "Page has no share image field; carried as a ref plus share_image_alt")
        if page.get("schema_type"):
            gaps.add(2, "page-schema-type", "Page has no per-page schema_type field (needs yield :structured_data)")
        if page.get("subnav") or page.get("subnav_hidden"):
            gaps.add(2, "page-subnav-flags", "Horizontal section sub-nav and subnav_hidden have no model")
        title = page.get("title") or page["name"]
        attrs = {"identifier": site.own_slug(file), "path": path, "privacy": "public", "published": True,
                 "position": order[parent], "source_file": file, "seo_title": seo_title(site, file),
                 "schema_type": page.get("schema_type", "WebPage"), "share_image_alt": page.get("image_alt"),
                 "subnav": bool(page.get("subnav")), "subnav_hidden": bool(page.get("subnav_hidden"))}
        tr = {"title": {"en": title}, "meta_description": {"en": page["description"]}}
        pages.append(record("page", key, attrs, tr, refs))
        with open(os.path.join(site.root, file), encoding="utf-8") as handle:
            body = extract_body(handle.read())
        if body is None:
            gaps.add(2, "page-without-main", f"{file} has no <main>")
            continue
        audit_body(body, file, gaps)
        pages.append(record("content_block", f"block:{path or 'home'}:body",
                            {"block_type": "html", "position": 0}, {"content_html": {"en": body}},
                            {"page": ref("page", key)}))
    return pages


def seo_title(site, file):
    name = site.meta["name"]
    if file == site.home:
        return name
    parts = [site.pages[f].get("title") or site.pages[f]["name"] for f in reversed(site.chain(file))]
    return " | ".join(parts + [name])


def build_navigation(site, gaps):
    recs = []
    for area, tree_parent in (("header", site.home),):
        recs.append(record("navigation_area", f"nav:{area}", {"name": area, "visible": True, "slug": area}))
        position = {}
        for file, page in site.pages.items():
            if file == site.home:
                continue
            parent = page.get("parent")
            depth = len(site.chain(file))
            if depth > 2:
                gaps.add(2, "nav-depth-3", "Third nav level; NavigationItem nesting depth is unverified", 1)
            position[parent] = position.get(parent, 0) + 1
            refs = {"area": ref("navigation_area", f"nav:{area}"), "page": ref("page", "page:" + site.path(file))}
            if parent and parent != site.home:
                refs["parent"] = ref("navigation_item", f"navitem:{area}:{site.path(parent)}")
            recs.append(record("navigation_item", f"navitem:{area}:{site.path(file)}",
                               {"position": position[parent], "visible": True}, {"title": {"en": page["name"]}}, refs))
    gaps.add(2, "header-nav-from-registry", "Header menu membership and order live in layout/partials/nav.html "
             "(hand edited); the packet derives the tree from site-nav.yml parents")
    recs.append(record("navigation_area", "nav:footer", {"name": "footer", "visible": True, "slug": "footer"}))
    for group in ("explore", "involved", "legal"):
        gkey = f"navitem:footer:group-{group}"
        recs.append(record("navigation_item", gkey, {"position": ("explore", "involved", "legal").index(group) + 1,
                                                    "visible": True, "heading": True},
                           {"title": {"en": group.capitalize()}}, {"area": ref("navigation_area", "nav:footer")}))
        for pos, file in enumerate(site.footer.get(group, []), 1):
            refs = {"area": ref("navigation_area", "nav:footer"), "parent": ref("navigation_item", gkey),
                    "page": ref("page", "page:" + (site.path(file) or "home"))}
            recs.append(record("navigation_item", f"navitem:footer:{site.path(file) or 'home'}",
                               {"position": pos, "visible": True}, {"title": {"en": site.pages[file]["name"]}}, refs))
    recs.append(record("content_block", "block:footer:tagline", {"block_type": "text", "slot": "footer_tagline"},
                       {"content": {"en": site.footer.get("tagline", "")}}, {"area": ref("navigation_area", "nav:footer")}))
    gaps.add(2, "footer-tagline", "Footer tagline has no host model; carried as a slotted content_block")
    return recs


def build_events(site, uploads_by_path, gaps):
    recs, seen = [], {}
    for foray in site.forays:
        seen[foray["year"]] = seen.get(foray["year"], 0) + 1
        key = f"event:foray-{foray['year']}" + (f"-{seen[foray['year']]}" if seen[foray["year"]] > 1 else "")
        attrs = {"year": foray["year"], "status": foray.get("status", "held"), "venue": foray.get("venue"),
                 "area": foray.get("area"), "starts_at": str(foray["start"]) if foray.get("start") else None,
                 "ends_at": str(foray["end"]) if foray.get("end") else None, "review_note": foray.get("note")}
        refs = {}
        if foray.get("page"):
            refs["page"] = ref("page", "page:" + site.path(foray["page"]))
        for field, path in (("report", foray.get("report")), ("card_art", (foray.get("art") or {}).get("file"))):
            up = uploads_by_path.get(path) if path else None
            if up:
                refs[field] = ref("upload", f"upload:{up['slug']}")
            elif path:
                gaps.add(4, "event-" + field + "-unresolved", f"{field} {path} is not an inventoried upload", 1)
        if not foray.get("start"):
            gaps.add(2, "event-without-dates", "Foray without a confirmed start date", 1)
        recs.append(record("event", key, attrs, {"name": {"en": foray["name"]}}, refs))
    gaps.add(2, "event-fields", "Event has no year, status (cancelled), venue/area structure or report/card refs; "
             "carried as plain attributes", len(recs))
    gaps.add(1, "event-import", "Posts/Events are export-only today; nothing creates local records from this", len(recs))
    return recs


def build_misc(site, gaps):
    socials = []
    for pos, account in enumerate(site.socials, 1):
        socials.append(record("social_media_account", f"social:{account['platform'].lower()}",
                              {"platform": account["platform"], "handle": account["handle"], "url": account["url"],
                               "position": pos, "icon": account["icon"]}))
        if account["platform"].lower() == "flickr":
            gaps.add(2, "social-flickr", "SocialMediaAccount::PLATFORMS has no Flickr; needs a ContactDetail parent")
    org = site.meta["organization"]
    org_rec = record("organization", "organization:main", {
        "site_name": site.meta["name"], "canonical_url": site.meta["url"], "locale": site.meta["locale"], **org})
    gaps.add(2, "organization-fields", "Legal name, telephone and locality have no confirmed Platform/Community fields")
    volumes = []
    for volume in site.omphalina:
        vkey = f"omphalina:volume-{volume['volume']}"
        volumes.append(record("omphalina_volume", vkey, {"volume": volume["volume"], "year": volume["year"]}, None,
                              {"page": ref("page", "page:" + site.path(volume["page"]))}))
        for issue in volume["issues"]:
            volumes.append(record("omphalina_issue", f"{vkey}:issue-{issue['issue']}",
                                  {"issue": issue["issue"], "position": issue["issue"]}, None,
                                  {"volume": ref("omphalina_volume", vkey), "pdf": ("@pdf", issue["pdf"]),
                                   "cover": ("@thumb", issue["thumb"])}))
    gaps.add(2, "omphalina-model", "Omphalina volumes and issues have no CE model; registered as new types",
             len(volumes))
    return socials, org_rec, volumes


def resolve_issue_refs(volumes, uploads_by_path):
    for rec in volumes:
        for name, value in list(rec.get("refs", {}).items()):
            if isinstance(value, tuple):
                up = uploads_by_path.get(value[1])
                rec["refs"][name] = ref("upload", f"upload:{up['slug']}") if up else None
                if rec["refs"][name] is None:
                    del rec["refs"][name]
        rec["fingerprint"] = fingerprint(rec)


def source_commit(root):
    try:
        out = subprocess.run(["git", "-C", root, "log", "-1", "--format=%H %cI"], capture_output=True, check=True)
        sha, stamp = out.stdout.decode().split()
        return sha, stamp
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        return None, "1970-01-01T00:00:00Z"


def build(site, uploads, prefix="en", upload_template=redirectlib.DEFAULT_UPLOAD_TEMPLATE):
    """Return (files, blobs, gaps): files maps 'records/x.yml' to a record list, plus the envelope data."""
    gaps = Gaps()
    by_path = {u["path"]: u for u in uploads if u["status"] == "ok"}
    upload_recs, blobs = build_uploads(uploads, gaps)
    pages = build_pages(site, by_path, gaps)
    nav = build_navigation(site, gaps)
    events = build_events(site, by_path, gaps)
    socials, org, volumes = build_misc(site, gaps)
    resolve_issue_refs(volumes, by_path)
    entries = redirectlib.build(site, uploads, prefix, upload_template)
    red = [dict(r, fingerprint=fingerprint(r)) for r in redirectlib.records(entries)]
    gaps.add(2, "redirect-model", "No Redirect model exists (work item D1); wildcard 404 rules and 410 are unsupported",
             len(red))
    gaps.add(2, "redirect-upload-url", f"Upload redirect target assumes the planned short path {upload_template} "
             "(work item B1); today it is /:locale/f/:id/download")
    gaps.add(10, "no-unplant", "No tombstone or unplant model; reruns can only add or upsert")
    gaps.add(6, "platform-target", "Packet requires an explicit platform: target; Seed is global on (type, identifier) today")
    gaps.add(12, "locale-en-only", "All content is en; the packet declares default_locale en and no other locales")
    gaps.add(16, "packet-source", "ALLOWED_SEED_DIRECTORIES blocks this packet's location (tmp/ or a host-app directory)")
    files = {"records/uploads.yml": upload_recs, "records/pages.yml": pages, "records/navigation.yml": nav,
             "records/events.yml": events + [org], "records/social_accounts.yml": socials,
             "records/omphalina.yml": volumes, "records/redirects.yml": red}
    gaps.add(4, "cross-record-refs", "References use {ref: {type, key}} resolved packet-local; counted in the report",
             sum(len(r.get("refs", {})) for recs in files.values() for r in recs))
    return files, blobs, gaps


def envelope(site, files, root):
    sha, stamp = source_commit(root)
    return {"better_together": {"version": "2.0", "seed": {
        "type": "BetterTogether::Seed", "identifier": PACKET_ID, "version": "1.0", "created_by": "foray-ce seed_packet.py",
        "created_at": stamp, "description": f"Content of {site.meta['url']} as a seed packet",
        "origin": {"lang": "en", "platforms": [], "source": {"repo": "foray-nl/nlmushrooms.ca", "commit": sha},
                   "key_id": None},
        "seed_pack": {"pack_type": "content", "install_tier": "optional", "marketing_name": site.meta["name"],
                      "dependencies": [], "selectable_in_setup_wizard": False, "installer": "seeds_plant"},
        "payload": {"target": {"platform": "required"}, "mode": "add_only", "default_locale": "en",
                    "unsupported_locale_policy": "skip_with_report", "records": sorted(files)}}}}


def manifest(files_text, blobs):
    entries = []
    for rel, text in sorted(files_text.items()):
        data = text.encode("utf-8")
        entries.append({"path": rel, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                        "media_type": "application/yaml", "owner": "packet"})
    for sha, info in sorted(blobs.items()):
        entries.append({"path": f"blobs/{sha}", "sha256": sha, "size": info["size"], "media_type": info["media_type"],
                        "owner": info["owners"]})
    return {"packet": PACKET_ID, "protocol": "2.0", "files": entries}


def dump(data):
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True, width=120)


def render(site, files, blobs, root):
    text = {rel: dump({"records": recs}) for rel, recs in files.items()}
    text["packet.yml"] = dump(envelope(site, files, root))
    man = manifest(text, blobs)
    text["MANIFEST.json"] = json.dumps(man, indent=2, ensure_ascii=False) + "\n"
    return text, man


def link_blob(src, dst, mode):
    if os.path.exists(dst):
        return
    if mode == "symlink":
        os.symlink(os.path.abspath(src), dst)
    elif mode == "hardlink":
        try:
            os.link(src, dst)
        except OSError:
            import shutil
            shutil.copyfile(src, dst)
    elif mode == "copy":
        import shutil
        shutil.copyfile(src, dst)


def write(out, text, blobs, root, blob_mode):
    os.makedirs(os.path.join(out, "records"), exist_ok=True)
    for rel, body in text.items():
        with open(os.path.join(out, rel), "w", encoding="utf-8") as handle:
            handle.write(body)
    if blob_mode == "none":
        return
    os.makedirs(os.path.join(out, "blobs"), exist_ok=True)
    for sha, info in blobs.items():
        link_blob(os.path.join(root, info["source"]), os.path.join(out, "blobs", sha), blob_mode)
