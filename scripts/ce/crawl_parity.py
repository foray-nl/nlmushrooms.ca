#!/usr/bin/env python3
"""Compares every old foray URL with the same URL on the new Community Engine site (read-only, bounded).

    python3 scripts/ce/crawl_parity.py --new https://ce.nlmushrooms.ca --dry-run
    python3 scripts/ce/crawl_parity.py --new https://ce.nlmushrooms.ca --old https://nlmushrooms.ca --out tmp/ce/parity.json

For each redirect-map entry it expects the status and one-hop Location, a 200 at the destination, matching
title, description, JSON-LD types, headings, link and alt counts for pages (against the old site), and with
--pdf-checksums the sha256 of each document against the file in this tree. Only GET requests; --delay spaces them.
Exit 1 when any entry has a problem.
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from foray_ce import inventory, parity, redirects, site  # noqa: E402


def main(argv=None, fetcher=None):
    root_default = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=root_default)
    parser.add_argument("--new", required=True, help="base URL of the new site, e.g. https://ce.nlmushrooms.ca")
    parser.add_argument("--old", help="base URL of the old site; omit to skip page comparison")
    parser.add_argument("--locale-prefix", default="en")
    parser.add_argument("--upload-url-template", default=redirects.DEFAULT_UPLOAD_TEMPLATE)
    parser.add_argument("--kinds", nargs="*", choices=["page", "netlify", "upload", "archive", "tooling"])
    parser.add_argument("--limit", type=int)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--delay", type=float, default=0.2)
    parser.add_argument("--pdf-checksums", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--dry-run", action="store_true", help="list the planned requests, send none")
    args = parser.parse_args(argv)
    s = site.Site(args.root)
    uploads = inventory.build(s, hash_files=args.pdf_checksums)
    sha_by_slug = {u["slug"]: u["sha256"] for u in uploads}
    entries = parity.plan(redirects.build(s, uploads, args.locale_prefix, args.upload_url_template),
                          args.old, args.new, args.kinds, args.limit)
    requests = sum(2 if e["status"] != 404 else 1 for e in entries) + (len(s.pages) if args.old else 0)
    if args.dry_run:
        print(json.dumps({"entries": len(entries), "planned_requests": requests, "new": args.new, "old": args.old}))
        return 0
    fetch = fetcher or parity.Fetcher(args.timeout, hash_bodies=args.pdf_checksums)
    old_pages = {}

    def old_cache(file):
        if file not in old_pages:
            old_pages[file] = fetch(args.old.rstrip("/") + "/" + file)
        return old_pages[file]

    results = []
    for entry in entries:
        slug = entry["to"].rsplit("/", 1)[-1] if entry["kind"] == "upload" else None
        results.append(parity.check_entry(entry, args.old, args.new.rstrip("/"), fetch,
                                          old_cache if args.old else None, sha_by_slug.get(slug)))
        time.sleep(args.delay)
    failed = [r for r in results if not r["ok"]]
    report = {"checked": len(results), "failed": len(failed), "results": failed}
    print(json.dumps({"checked": len(results), "failed": len(failed)}))
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
