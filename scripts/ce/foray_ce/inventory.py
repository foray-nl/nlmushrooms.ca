"""The Upload inventory: every public PDF, spreadsheet and site image with a slug, title and checksum."""
import os
import re

from . import site as sitelib

KIND = {".pdf": "document", ".xlsx": "spreadsheet"}


def humanize(rel):
    stem = os.path.splitext(os.path.basename(rel))[0]
    return re.sub(r"\s+", " ", re.sub(r"[_]+", " ", stem)).strip()


def _report_titles(site):
    """report path -> (years, title, slug): one report PDF can cover several forays."""
    years = {}
    for foray in site.forays:
        if foray.get("report"):
            years.setdefault(foray["report"], []).append(foray["year"])
    out = {}
    for path, ys in years.items():
        ys = sorted(ys)
        label = " and ".join(str(y) for y in ys)
        out[path] = (ys, f"Foray {label} report", "foray-report-" + "-".join(str(y) for y in ys))
    return out


def _alt_texts(site):
    alts = {}
    for foray in site.forays:
        art = foray.get("art") or {}
        if art.get("file") and foray.get("art_alt"):
            alts[art["file"]] = foray["art_alt"]
    for volume in site.omphalina:
        for issue in volume["issues"]:
            label = sitelib.issue_label(volume["volume"], issue["issue"], volume["year"])
            alts[issue["thumb"]] = f"Cover of {label}"
    meta = site.meta
    if meta.get("image") and meta.get("image_alt"):
        alts[meta["image"]] = meta["image_alt"]
    for page in site.pages.values():
        if page.get("image") and page.get("image_alt"):
            alts[page["image"]] = page["image_alt"]
    return alts


def build(site, files=None, hash_files=True):
    """Return Upload dicts sorted by path. `status` is ok, lfs_pointer or missing."""
    root = site.root
    files = files if files is not None else sitelib.tracked_files(root)
    docs = sitelib.public_pdfs(root, files)
    images = sitelib.site_images(root, files)
    reports = _report_titles(site)
    titles, preferred = {}, {}
    for volume in site.omphalina:
        for issue in volume["issues"]:
            label = sitelib.issue_label(volume["volume"], issue["issue"], volume["year"])
            titles[issue["pdf"]] = label
            preferred[issue["pdf"]] = f"omphalina-{sitelib.roman(volume['volume'])}-{issue['issue']}"
    for path, (_ys, title, slug) in reports.items():
        titles[path], preferred[path] = title, slug
    alts = _alt_texts(site)
    slugs = sitelib.upload_slugs(docs + images, preferred)
    uploads = []
    for rel in sorted(docs + images):
        full = os.path.join(root, rel)
        status = "ok"
        if not os.path.exists(full):
            status = "missing"
        elif sitelib.is_lfs_pointer(full):
            status = "lfs_pointer"
        entry = {
            "path": rel, "slug": slugs[rel], "kind": KIND.get(os.path.splitext(rel)[1].lower(), "image"),
            "title": titles.get(rel) or humanize(rel), "alt": alts.get(rel),
            "content_type": sitelib.content_type(rel), "filename": os.path.basename(rel),
            "status": status, "size": os.path.getsize(full) if status != "missing" else 0, "sha256": None,
        }
        if hash_files and status == "ok":
            entry["sha256"] = sitelib.sha256_of(full)
        uploads.append(entry)
    return uploads


def summarize(uploads):
    out = {"total": len(uploads), "bytes": sum(u["size"] for u in uploads), "by_kind": {}, "by_status": {},
           "largest": None}
    for item in uploads:
        out["by_kind"][item["kind"]] = out["by_kind"].get(item["kind"], 0) + 1
        out["by_status"][item["status"]] = out["by_status"].get(item["status"], 0) + 1
    if uploads:
        big = max(uploads, key=lambda u: u["size"])
        out["largest"] = {"path": big["path"], "size": big["size"]}
    return out
