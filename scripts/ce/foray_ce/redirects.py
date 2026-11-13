"""Redirect map: every old URL of the static site to its clean CE path (or a deliberate 404), one hop each."""
import os
import re
from urllib.parse import unquote

from . import site as sitelib

DEFAULT_UPLOAD_TEMPLATE = "/f/{slug}"


class RedirectError(Exception):
    pass


def target(prefix, path):
    base = "/" + prefix.strip("/") if prefix else ""
    return f"{base}/{path}" if path else (base or "/")


def netlify_rules(root):
    """The [[redirects]] tables of netlify.toml (flat string and integer keys; no TOML library needed)."""
    rules, current = [], None
    with open(os.path.join(root, "netlify.toml"), encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("["):
                current = {} if line == "[[redirects]]" else None
                if current is not None:
                    rules.append(current)
                continue
            match = re.match(r'(\w+)\s*=\s*(?:"([^"]*)"|(\w+))\s*$', line)
            if current is not None and match:
                value = match.group(2) if match.group(2) is not None else match.group(3)
                current[match.group(1)] = int(value) if value.isdigit() else value
    return rules


def _page_for_old(site, to_path):
    name = unquote(to_path).lstrip("/")
    return name if name in site.pages else None


def build(site, uploads, prefix="en", upload_template=DEFAULT_UPLOAD_TEMPLATE, include_images=False):
    """Return entries {from, to, status, kind, source}; raises RedirectError on conflicts or chains."""
    entries = []

    def add(src, dest, status, kind, source):
        if src == dest:
            return
        entries.append({"from": src, "to": dest, "status": status, "kind": kind, "source": source})

    for file in site.pages:
        dest = target(prefix, site.path(file))
        for old in site.old_paths(file):
            if old != "/":
                add(old, dest, 301, "page", file)
    for rule in netlify_rules(site.root):
        src, dest, status = rule["from"], rule.get("to"), rule.get("status", 301)
        if status == 404:
            kind = "archive" if src.startswith("/archive") else "tooling"
            add(src, None, 404, kind, "netlify.toml")
            continue
        file = _page_for_old(site, dest)
        if file is None:
            raise RedirectError(f"netlify rule {src} points at {dest}, which is not a registered page")
        add(src, target(prefix, site.path(file)), status, "netlify", "netlify.toml")
    for item in uploads:
        if item["kind"] == "image" and not include_images:
            continue
        dest = upload_template.format(slug=item["slug"])
        for form in sitelib.url_forms("/" + item["path"]):
            add(form, dest, 301, "upload", item["path"])
    return validate(dedupe(entries))


def dedupe(entries):
    """Drop exact duplicates (same from and to); keep order of first appearance."""
    seen, out = set(), []
    for entry in entries:
        key = (entry["from"], entry["to"], entry["status"])
        if key not in seen:
            seen.add(key)
            out.append(entry)
    return out


def validate(entries):
    by_from = {}
    for entry in entries:
        if entry["from"] in by_from:
            raise RedirectError(f"conflicting rules for {entry['from']}: {by_from[entry['from']]['to']} vs {entry['to']}")
        by_from[entry["from"]] = entry
    for entry in entries:
        if entry["to"] and entry["to"] in by_from:
            raise RedirectError(f"redirect chain: {entry['from']} -> {entry['to']} -> {by_from[entry['to']]['to']}")
    return entries


def records(entries):
    out = []
    for entry in entries:
        out.append({
            "type": "redirect", "key": f"redirect:{entry['from']}",
            "attributes": {"from_path": entry["from"], "to_path": entry["to"], "status": entry["status"],
                           "match": "prefix" if entry["from"].endswith("/*") else "exact", "kind": entry["kind"],
                           "source": entry["source"]},
        })
    return out
