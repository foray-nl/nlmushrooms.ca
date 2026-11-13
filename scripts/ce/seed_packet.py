#!/usr/bin/env python3
"""Builds the foray seed packet (protocol 2.0 draft layout) from layout/*.yml and the site files.

    python3 scripts/ce/seed_packet.py --dry-run                 plan only: counts, sizes, gaps, nothing written
    python3 scripts/ce/seed_packet.py --out tmp/ce/foray-nl-site [--blobs hardlink|symlink|copy|none]

Blobs are hard links (copy fallback) to the files already in the tree, so the 638 MB of PDFs are never duplicated.
The output must live under tmp/ (gitignored) or outside the repository. Exit 3 when files are still LFS pointers.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from foray_ce import inventory, packet, redirects, site  # noqa: E402


def check_out(root, out):
    root, out = os.path.realpath(root), os.path.realpath(out)
    inside = out == root or out.startswith(root + os.sep)
    if inside and not out.startswith(os.path.join(root, "tmp") + os.sep):
        raise SystemExit("error: --out inside the repository must be under tmp/ (gitignored)")


def main(argv=None):
    root_default = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=root_default)
    parser.add_argument("--out")
    parser.add_argument("--blobs", choices=["hardlink", "symlink", "copy", "none"], default="hardlink")
    parser.add_argument("--locale-prefix", default="en")
    parser.add_argument("--upload-url-template", default=redirects.DEFAULT_UPLOAD_TEMPLATE)
    parser.add_argument("--allow-pointers", action="store_true", help="continue when some files are LFS pointers")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    s = site.Site(args.root)
    uploads = inventory.build(s)
    summary = inventory.summarize(uploads)
    pointers = summary["by_status"].get("lfs_pointer", 0)
    files, blobs, gaps = packet.build(s, uploads, args.locale_prefix, args.upload_url_template)
    text, man = packet.render(s, files, blobs, args.root)
    report = {"uploads": summary, "records": {rel: len(recs) for rel, recs in sorted(files.items())},
              "blobs": len(blobs), "manifest_files": len(man["files"]), "gaps": gaps.as_list()}
    print(json.dumps(report, indent=2))
    if pointers and not args.allow_pointers:
        print(f"error: {pointers} files are LFS pointers; run `git lfs pull` (dry-run: git lfs ls-files)", file=sys.stderr)
        return 3
    if args.dry_run or not args.out:
        return 0
    check_out(args.root, args.out)
    packet.write(args.out, text, blobs, args.root, args.blobs)
    with open(os.path.join(args.out, "gaps.json"), "w", encoding="utf-8") as handle:
        json.dump(report["gaps"], handle, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
