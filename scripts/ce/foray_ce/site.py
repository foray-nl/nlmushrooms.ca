"""Shared model of the static site: registries, slug rules, URL forms and the file inventory.

Everything here is read-only and hermetic: it reads `layout/*.yml` and the file tree under a given root.
"""
import hashlib
import mimetypes
import os
import re
import subprocess
import unicodedata

import yaml

EXCLUDE_DIRS = ("tmp", "docs", "archive", "layout", "vendor", "spec", "scripts", "manifests", "assets", "node_modules")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")
IMAGE_DIRS = ("images", "_wp_generated")
ROMAN = ((10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"))


def read_yaml(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def slugify(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def roman(number):
    out = ""
    for value, symbol in ROMAN:
        while number >= value:
            out += symbol
            number -= value
    return out


class Site:
    """The page registry plus the optional slug overrides in layout/ce-slugs.yml."""

    def __init__(self, root):
        self.root = root
        data = read_yaml(root, "layout/site-nav.yml")
        self.meta = data["site"]
        self.pages = {p["file"]: p for p in data["pages"]}
        self.home = next(f for f, p in self.pages.items() if "parent" not in p)
        path = os.path.join(root, "layout/ce-slugs.yml")
        self.overrides = read_yaml(root, "layout/ce-slugs.yml") or {} if os.path.exists(path) else {}
        self.forays = read_yaml(root, "layout/forays.yml") or []
        self.omphalina = read_yaml(root, "layout/omphalina.yml") or []
        self.socials = read_yaml(root, "layout/socials.yml") or []
        self.footer = read_yaml(root, "layout/footer.yml") or {}

    def own_slug(self, file):
        if file == self.home:
            return "home"
        return self.overrides.get(file) or slugify(file[: -len(".html")].replace("_", "-"))

    def chain(self, file):
        """Page files from the top-level ancestor down to `file`, home excluded."""
        out = []
        while file and file != self.home:
            out.append(file)
            file = self.pages[file].get("parent")
        return list(reversed(out))

    def path(self, file):
        """Clean CE path without a locale prefix: '' for home, else 'past-forays/foray-2025'."""
        if file == self.home:
            return ""
        return "/".join(self.own_slug(f) for f in self.chain(file))

    def old_paths(self, file):
        """Every URL form the static site answered for a page, with a leading slash."""
        stem = file[: -len(".html")]
        forms = [f"/{file}", f"/{stem}"]
        if file == self.home:
            forms = ["/", "/index.html", "/index"]
        return forms


def url_forms(path):
    """A path and its URL-encoded form (spaces, non-ASCII), deduplicated, raw form first."""
    from urllib.parse import quote

    forms = [path]
    encoded = quote(path, safe="/")
    if encoded != path:
        forms.append(encoded)
    return forms


def tracked_files(root):
    """Tracked files relative to root (git ls-files), or a directory walk outside a git checkout."""
    if os.path.exists(os.path.join(root, ".git")):
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
        return sorted(f for f in out.decode("utf-8").split("\0") if f)
    found = []
    for base, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in names:
            found.append(os.path.relpath(os.path.join(base, name), root))
    return sorted(found)


def is_public(rel):
    return rel.split("/")[0] not in EXCLUDE_DIRS and "/" + rel != "/404.html"


def is_lfs_pointer(path):
    with open(path, "rb") as handle:
        return handle.read(40).startswith(b"version https://git-lfs")


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def content_type(rel):
    return mimetypes.guess_type(rel)[0] or "application/octet-stream"


def public_pdfs(root, files=None):
    files = files if files is not None else tracked_files(root)
    return [f for f in files if f.lower().endswith((".pdf", ".xlsx")) and is_public(f)]


def site_images(root, files=None):
    files = files if files is not None else tracked_files(root)
    return [f for f in files if f.lower().endswith(IMAGE_EXT) and f.split("/")[0] in IMAGE_DIRS]


def issue_label(volume, issue, year):
    return f"Omphalina Volume {roman(volume).upper()}, No. {issue} ({year})"


def upload_slugs(paths, preferred):
    """Slug per path: `preferred` wins, else the file stem; a collision gets the directory, then a counter."""
    taken, out = {}, {}
    for rel in sorted(paths):
        base = preferred.get(rel) or slugify(os.path.splitext(os.path.basename(rel))[0])
        slug = base
        if slug in taken:
            slug = slugify(os.path.dirname(rel) + "-" + base) if os.path.dirname(rel) else base
        counter = 2
        while slug in taken:
            slug = f"{base}-{counter}"
            counter += 1
        taken[slug] = rel
        out[rel] = slug
    return out
