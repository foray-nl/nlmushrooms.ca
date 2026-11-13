#!/usr/bin/env python3
"""Writes the old-URL to clean-CE-path redirect map.

    python3 scripts/ce/redirect_map.py --dry-run
    python3 scripts/ce/redirect_map.py --out tmp/ce/redirects.yml --format yml|json|csv

Nothing is written without --out. --no-hash skips checksumming the PDFs (the map does not need them).
"""
import argparse
import csv
import io
import json
import os
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from foray_ce import inventory, redirects, site  # noqa: E402


def render(entries, fmt):
    if fmt == "json":
        return json.dumps(entries, indent=2, ensure_ascii=False) + "\n"
    if fmt == "csv":
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=["from", "to", "status", "kind", "source"])
        writer.writeheader()
        writer.writerows(entries)
        return buf.getvalue()
    return yaml.safe_dump({"records": redirects.records(entries)}, sort_keys=False, allow_unicode=True)


def main(argv=None):
    root_default = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=root_default)
    parser.add_argument("--out")
    parser.add_argument("--format", choices=["yml", "json", "csv"], default="yml")
    parser.add_argument("--locale-prefix", default="en", help="locale segment of the CE paths; empty for none")
    parser.add_argument("--upload-url-template", default=redirects.DEFAULT_UPLOAD_TEMPLATE)
    parser.add_argument("--include-images", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="print counts only, write nothing")
    args = parser.parse_args(argv)
    s = site.Site(args.root)
    try:
        entries = redirects.build(s, inventory.build(s, hash_files=False), args.locale_prefix,
                                  args.upload_url_template, args.include_images)
    except redirects.RedirectError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    counts = {}
    for entry in entries:
        counts[entry["kind"]] = counts.get(entry["kind"], 0) + 1
    print(json.dumps({"total": len(entries), "by_kind": counts}))
    if args.out and not args.dry_run:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(render(entries, args.format))
    return 0


if __name__ == "__main__":
    sys.exit(main())
