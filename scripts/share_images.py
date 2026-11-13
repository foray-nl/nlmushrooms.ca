#!/usr/bin/env python3
"""Builds the 1200x630 Open Graph / Twitter share images in images/share/ (needs Pillow).

    python3 scripts/share_images.py

default.jpg: the logo banner centred on the banner's brown. foray-<year>.jpg: that year's poster scaled to the full
height and centred on dark navy. To add a year, add its poster to POSTERS and `image:` to its entry in layout/site-nav.yml.
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'images', 'share')
SIZE = (1200, 630)
BANNER = '_wp_generated/wp1da48039_05_06.jpg'
POSTERS = {2024: 'images/foray2024_poster.png', 2025: 'images/Foray-2025-Poster.png', 2026: 'images/Foray-2026-Poster.png'}


def compose(background, source, fit, name):
    img = Image.open(os.path.join(ROOT, source)).convert('RGB')
    scale = fit(img.size)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    canvas = Image.new('RGB', SIZE, background)
    canvas.paste(img, ((SIZE[0] - img.width) // 2, (SIZE[1] - img.height) // 2))
    canvas.save(os.path.join(OUT, name), 'JPEG', quality=86, optimize=True)


os.makedirs(OUT, exist_ok=True)
compose('#9c7236', BANNER, lambda s: 1100 / s[0], 'default.jpg')
for year, poster in POSTERS.items():
    compose('#243542', poster, lambda s: 590 / s[1], f'foray-{year}.jpg')
for name in sorted(os.listdir(OUT)):
    print(name, Image.open(os.path.join(OUT, name)).size, os.path.getsize(os.path.join(OUT, name)) // 1024, 'KB')
