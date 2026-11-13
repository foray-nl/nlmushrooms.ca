#!/usr/bin/env python3
"""Builds the card images in images/forays/<year>.jpg (420 px wide) from the `art` sources in layout/forays.yml.

    python3 scripts/foray_card_images.py [year ...]

Needs Pillow, PyYAML and poppler's pdftoppm. A source is {pdf: path, page: n} (that page is rendered) or {file: path}.
"""
import os
import subprocess
import sys
import tempfile

import yaml
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'images', 'forays')
WIDTH = 420


def render(art, tmp):
    if 'file' in art:
        return Image.open(os.path.join(ROOT, art['file'])).convert('RGB')
    base = os.path.join(tmp, 'page')
    subprocess.run(['pdftoppm', '-r', '72', '-f', str(art['page']), '-l', str(art['page']), '-png',
                    os.path.join(ROOT, art['pdf']), base], check=True)
    png = next(os.path.join(tmp, f) for f in sorted(os.listdir(tmp)) if f.startswith('page'))
    return Image.open(png).convert('RGB')


def main(years):
    forays = yaml.safe_load(open(os.path.join(ROOT, 'layout', 'forays.yml')))
    os.makedirs(OUT, exist_ok=True)
    for f in forays:
        if 'art' not in f or (years and str(f['year']) not in years):
            continue
        with tempfile.TemporaryDirectory() as tmp:
            img = render(f['art'], tmp)
        img = img.resize((WIDTH, round(img.height * WIDTH / img.width)), Image.LANCZOS)
        path = os.path.join(OUT, f"{f['year']}.jpg")
        img.save(path, 'JPEG', quality=80, optimize=True)
        print(f"{f['year']}: {img.size[0]}x{img.size[1]}, {os.path.getsize(path) // 1024} KB")


main(sys.argv[1:])
