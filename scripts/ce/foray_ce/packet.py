"""Seed packet for the foray site, following seed_packet_protocol.md (protocol 2.0, CE branch feat/seed-protocol-2-spec).

packet.yml, MANIFEST.json, one records/<type>.yml per record type and blobs/<sha256>. Every place where the
protocol or the CE models cannot carry the data is recorded in the gap log against the numbered deficiency list.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess

import yaml

from . import redirects as redirectlib
from . import site as sitelib

PACKET_ID = "foray-nl-site"
COMMUNITY_KEY = "foray-nl"
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


def ref(rtype, key):
    return f"{rtype}:{key}"


def record(key, attributes, translations=None, refs=None, files=None, position=None):
    out = {"key": key, "attributes": attributes}
    if translations:
        out["translations"] = translations
    if refs:
        out["refs"] = refs
    if files:
        out["files"] = files
    if position is not None:
        out["position"] = position
    return out


def locale_first(fields):
    """{'title': {'en': 'x'}} -> {'en': {'title': 'x'}} (the protocol keeps translations per locale)."""
    out = {}
    for name, per_locale in fields.items():
        for locale, value in per_locale.items():
            out.setdefault(locale, {})[name] = value
    return out


def page_key(site, file):
    return site.path(file) or "home"


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
        gaps.add(4, "inline-images-need-upload-refs", "Inline <img> src values are old paths; the protocol has no "
                 "in-body file reference syntax", imgs)


def file_entry(item, attachment):
    return {"attachment": attachment, "blob": f"blobs/{item['sha256']}", "filename": item["filename"],
            "content_type": item["content_type"], "checksum": item["sha256"]}


def build_uploads(site, uploads, gaps):
    recs, blobs = [], {}
    owner = site.meta["organization"]["legal_name"]
    for item in uploads:
        if item["status"] != "ok":
            gaps.add(3, "blob-" + item["status"], "File has no real bytes (git lfs pull or locate it)")
            continue
        entry = file_entry(item, "file")
        if item["alt"]:
            entry["alt"] = {"en": item["alt"]}
        recs.append(record(item["slug"], {"privacy": "public"}, {"en": {"name": item["title"]}}, files=[entry]))
        blobs.setdefault(item["sha256"], {"source": item["path"], "size": item["size"], "owner": owner,
                                          "media_type": item["content_type"]})
    big = [u for u in uploads if u["size"] > 10 * 1024 * 1024]
    gaps.add(3, "blob-total", f"{sum(u['size'] for u in uploads)} bytes in {len(blobs)} blobs; the 10 MB cap covers the "
             "YAML only, so blobs need streaming reads and per-blob size policy", len(blobs))
    if big:
        gaps.add(3, "blob-over-10mb", "Blobs over 10 MB (largest need streaming)", len(big))
    gaps.add(3, "blob-licence-unknown", "Manifest has owner and license per file; the licence of the foray images "
             "and documents is not recorded in the repository (owner set to the organization)", len(blobs))
    gaps.add(2, "upload-source-path", "Upload has no source path or kind field; the old path survives only in the "
             "redirect map", len(recs))
    ods = [u for u in uploads if u["kind"] == "spreadsheet"]
    if ods:
        gaps.add(2, "spreadsheet-upload", "Confirm Upload accepts .xlsx (species_lists/Omphalina contents.xlsx)", len(ods))
    return recs, blobs


def seo_title(site, file):
    name = site.meta["name"]
    if file == site.home:
        return name
    parts = [site.pages[f].get("title") or site.pages[f]["name"] for f in reversed(site.chain(file))]
    return " | ".join(parts + [name])


def build_pages(site, uploads_by_path, gaps):
    pages, blocks, page_blocks, order = [], [], [], {}
    published_at = source_commit(site.root)[1]
    for file, page in site.pages.items():
        parent = page.get("parent")
        order[parent] = order.get(parent, 0) + 1
        key = page_key(site, file)
        if page.get("image"):
            gaps.add(2, "page-share-image", "Page has no share image field or alt; the share image is not carried")
        if page.get("schema_type"):
            gaps.add(2, "page-schema-type", "Page has no per-page schema_type field (needs yield :structured_data)")
        if page.get("subnav") or page.get("subnav_hidden"):
            gaps.add(2, "page-subnav-flags", "Horizontal section sub-nav and subnav_hidden have no model")
        gaps.add(2, "page-position", "Page and SocialMediaAccount have no position column; sibling order is not carried")
        gaps.add(2, "page-seo-title", "Page has no separate SEO title; the page title is used")
        # Nested pages carry their path as the slug (about/mission); the Page type has no parent reference.
        attrs = {"slug": key, "privacy": "public", "published_at": published_at, "show_title": True,
                 "meta_description": page["description"]}
        pages.append(record(key, attrs, {"en": {"title": page.get("title") or page["name"]}},
                            {"community": ref("community", COMMUNITY_KEY)}))
        with open(os.path.join(site.root, file), encoding="utf-8") as handle:
            body = extract_body(handle.read())
        if body is None:
            gaps.add(2, "page-without-main", f"{file} has no <main>")
            continue
        audit_body(body, file, gaps)
        bkey = f"{key}.body"
        blocks.append(record(bkey, {"type": "BetterTogether::Content::Html", "privacy": "public", "visible": True,
                                    "content_data": {"html_content": body}}, {"en": {"content": body}}))
        page_blocks.append(record(f"{key}/body", {}, refs={"page": ref("page", key), "block": ref("content_block", bkey)},
                                  position=0))
    return pages, blocks, page_blocks


def build_navigation(site, gaps):
    areas = [record("header", {"visible": True}, {"en": {"name": "Header"}}),
             record("footer", {"visible": True}, {"en": {"name": "Footer"}})]
    items, position = [], {}
    for file, page in site.pages.items():
        if file == site.home:
            continue
        parent = page.get("parent")
        if len(site.chain(file)) > 2:
            gaps.add(2, "nav-depth-3", "Third nav level; NavigationItem nesting depth is unverified")
        position[parent] = position.get(parent, 0) + 1
        refs = {"navigation_area": ref("navigation_area", "header"), "linkable": ref("page", page_key(site, file))}
        if parent and parent != site.home:
            refs["parent"] = ref("navigation_item", f"header/{site.path(parent)}")
        items.append(record(f"header/{site.path(file)}", {"item_type": "link", "visible": True, "privacy": "public"},
                            None, refs, position=position[parent]))
    gaps.add(2, "nav-label-from-page", "NavigationItem#title delegates to the linked page, so short menu labels "
             "(site-nav name) cannot differ from the page title; items omit title and show the page title")
    gaps.add(2, "header-nav-from-registry", "Header menu membership and order live in layout/partials/nav.html "
             "(hand edited); the packet derives the tree from site-nav.yml parents")
    for index, group in enumerate(("explore", "involved", "legal")):
        gkey = f"footer/group-{group}"
        items.append(record(gkey, {"item_type": "dropdown", "visible": True, "privacy": "public"},
                            {"en": {"title": group.capitalize()}},
                            {"navigation_area": ref("navigation_area", "footer")}, position=index))
        for pos, file in enumerate(site.footer.get(group, [])):
            refs = {"navigation_area": ref("navigation_area", "footer"), "parent": ref("navigation_item", gkey),
                    "linkable": ref("page", page_key(site, file))}
            items.append(record(f"footer/{page_key(site, file)}", {"item_type": "link", "visible": True,
                                                                 "privacy": "public"},
                                None, refs, position=pos))
    if site.footer.get("tagline"):
        gaps.add(2, "footer-tagline", "Footer tagline has no host model or slot; not carried (host app footer partial)")
    return areas, items


STATUS = {"held": "confirmed", "cancelled": "cancelled"}


def build_events(site, uploads_by_path, gaps):
    recs, seen = [], {}
    for foray in site.forays:
        seen[foray["year"]] = seen.get(foray["year"], 0) + 1
        key = f"foray-{foray['year']}" + (f"-{seen[foray['year']]}" if seen[foray["year"]] > 1 else "")
        attrs = {"privacy": "public", "status": STATUS.get(foray.get("status", "held"), "draft"),
                 "timezone": "America/St_Johns"}
        if foray.get("start"):
            attrs["starts_at"] = str(foray["start"])
        if foray.get("end"):
            attrs["ends_at"] = str(foray["end"])
        where = ", ".join(x for x in (foray.get("venue"), foray.get("area")) if x)
        tr = {"name": foray["name"]}
        if where:
            tr["description"] = where
        files = []
        art = (foray.get("art") or {}).get("file")
        up = uploads_by_path.get(art) if art else None
        if up:
            files.append(file_entry(up, "cover_image"))
        elif art:
            gaps.add(4, "event-card_art-unresolved", f"card_art {art} is not an inventoried upload (missing file)")
        if foray.get("report"):
            gaps.add(2, "event-report-ref", "Event has no report link; the report PDF stays an Upload and a page link")
        if not foray.get("start"):
            gaps.add(2, "event-without-dates", "Foray without a confirmed start date")
        recs.append(record(key, attrs, {"en": tr}, files=files or None))
    gaps.add(2, "event-fields", "Event has no year, venue or area fields; venue and area are folded into the "
             "description, year comes from starts_at", len(recs))
    return recs


def build_misc(site, uploads_by_path, gaps):
    org = site.meta["organization"]
    files = []
    logo = uploads_by_path.get(org.get("logo"))
    if logo:
        files.append(file_entry(logo, "logo"))
    community = record(COMMUNITY_KEY, {"privacy": "public"},
                       {"en": {"name": site.meta["name"], "description": site.pages[site.home]["description"]}},
                       files=files or None)
    contact = record("main", {}, refs={"contactable": ref("community", COMMUNITY_KEY)})
    gaps.add(2, "organization-fields", "Legal name, email, telephone and locality have no registered seed types "
             "(EmailAddress, PhoneNumber, Address) or fields; not carried")
    socials = []
    for pos, account in enumerate(site.socials):
        socials.append(record(account["platform"].lower(),
                              {"platform_name": account["platform"], "handle": account["handle"],
                               "url": account["url"], "privacy": "public"},
                              refs={"contact_detail": ref("contact_detail", "main")}))
        if account["platform"].lower() == "flickr":
            gaps.add(2, "social-flickr", "SocialMediaAccount::PLATFORMS has no Flickr")
    gaps.add(2, "social-icon", "SocialMediaAccount has no icon field; the icon follows the platform", len(socials))
    omphalina = sum(len(v["issues"]) + 1 for v in site.omphalina)
    gaps.add(2, "omphalina-model", "Omphalina volumes and issues have no seed type; the volume pages carry the issue "
             "grid in their body and every issue PDF and cover is an Upload", omphalina)
    return community, contact, socials


def source_commit(root):
    try:
        out = subprocess.run(["git", "-C", root, "log", "-1", "--format=%H %cI"], capture_output=True, check=True)
        sha, stamp = out.stdout.decode().split()
        return sha, stamp
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        return None, "1970-01-01T00:00:00Z"


def build(site, uploads, prefix="en", upload_template=redirectlib.DEFAULT_UPLOAD_TEMPLATE):
    """Return ({'records/x.yml': (type, [records])}, blobs, gaps)."""
    gaps = Gaps()
    by_path = {u["path"]: u for u in uploads if u["status"] == "ok"}
    upload_recs, blobs = build_uploads(site, uploads, gaps)
    pages, blocks, page_blocks = build_pages(site, by_path, gaps)
    areas, items = build_navigation(site, gaps)
    events = build_events(site, by_path, gaps)
    community, contact, socials = build_misc(site, by_path, gaps)
    reds = redirectlib.records(redirectlib.build(site, uploads, prefix, upload_template))
    prefix_rules = [e for e in redirectlib.build(site, uploads, prefix, upload_template) if e["from"].endswith("/*")]
    if prefix_rules:
        gaps.add(2, "redirect-prefix-rules", "Redirect matches exact paths only; wildcard rules are not carried",
                 len(prefix_rules))
    gaps.add(2, "redirect-gone", "Redirect supports 410 but no deliberate-404 rule type; forced 404 paths are dropped")
    gaps.add(2, "redirect-upload-url", f"Upload redirect target assumes the planned short path {upload_template} "
             "(work item B1); today it is /:locale/f/:id/download")
    gaps.add(2, "layout-one-type-per-file", "The plan listed records/{uploads,pages,navigation,...}.yml; the C1 spec "
             "allows one type per file, so content blocks and nav items have their own files")
    gaps.add(5, "provenance", "Stable natural keys are emitted; fingerprint and provenance columns belong to the planter (C7)")
    gaps.add(6, "platform-target", "Packet carries no target; the caller supplies PLATFORM= (spec). Seed is still "
             "global on (type, identifier) until C7")
    gaps.add(10, "no-unplant", "No tombstone or unplant model; reruns can only add or upsert")
    gaps.add(12, "locale-en-only", "All content is en; the packet declares default_locale en and locales [en]")
    gaps.add(16, "packet-source", "Packets outside config/seeds need BETTER_TOGETHER_SEED_PACKET_ROOTS (resolved by "
             "Seeds::PacketSources, not a blocker)")
    files = {"records/uploads.yml": ("upload", upload_recs), "records/communities.yml": ("community", [community]),
             "records/contact_details.yml": ("contact_detail", [contact]),
             "records/social_media_accounts.yml": ("social_media_account", socials),
             "records/pages.yml": ("page", pages), "records/content_blocks.yml": ("content_block", blocks),
             "records/page_blocks.yml": ("page_block", page_blocks),
             "records/navigation_areas.yml": ("navigation_area", areas),
             "records/navigation_items.yml": ("navigation_item", items), "records/events.yml": ("event", events),
             "records/redirects.yml": ("redirect", reds)}
    gaps.add(4, "cross-record-refs", "References use the type:key string form resolved packet-local; counted here",
             sum(len(r.get("refs", {})) for _t, recs in files.values() for r in recs))
    return files, blobs, gaps


def envelope(site, files, root):
    sha, stamp = source_commit(root)
    notes = f"Generated by scripts/ce/seed_packet.py from {sha}" if sha else "Generated by scripts/ce/seed_packet.py"
    return {"better_together": {"version": "2.0", "seed": {
        "type": "BetterTogether::Seed", "identifier": PACKET_ID, "created_by": "foray-ce seed_packet.py",
        "created_at": stamp, "description": f"Content of {site.meta['url']} as a seed packet",
        "origin": {"platforms": [], "contributors": [site.meta["organization"]["legal_name"]], "usage_notes": notes}},
        "seed_pack": {"schema_version": "1.0", "pack_type": "content", "install_tier": "optional",
                      "marketing_name": site.meta["name"], "selectable_in_setup_wizard": False, "dependencies": []},
        "packet": {"id": PACKET_ID, "version": "1.0.0", "mode": "add_only", "default_locale": "en", "locales": ["en"],
                   "unsupported_locale_policy": "skip", "records": sorted(files), "manifest": "MANIFEST.json"}}}


def manifest(site, files_text, blobs, stamp):
    owner = site.meta["organization"]["legal_name"]
    entries = []
    for rel, text in sorted(files_text.items()):
        data = text.encode("utf-8")
        entries.append({"path": rel, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                        "media_type": "application/yaml", "owner": owner})
    for sha, info in sorted(blobs.items()):
        entries.append({"path": f"blobs/{sha}", "sha256": sha, "size": info["size"], "media_type": info["media_type"],
                        "owner": info["owner"]})
    return {"schema": "2.0", "algorithm": "sha256", "packet_id": PACKET_ID, "generated_at": stamp, "files": entries}


def dump(data):
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True, width=120)


def render(site, files, blobs, root):
    text = {rel: dump({"version": "2.0", "type": rtype, "records": recs}) for rel, (rtype, recs) in files.items()}
    text["packet.yml"] = dump(envelope(site, files, root))
    stamp = source_commit(root)[1]
    man = manifest(site, text, blobs, stamp)
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
            shutil.copyfile(src, dst)
    elif mode == "copy":
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
