"""The Foray theme tokens must be valid CE theme settings and readable (WCAG AA)."""
import json
import re
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "platform_theme.json"
PAIRS = [("primary_text", "primary"), ("navbar_link", "navbar_bg"), ("footer_link", "footer_bg"),
         ("body_text", "band"), ("link", "band")]


def luminance(hex_color):
    channels = []
    for i in (1, 3, 5):
        c = int(hex_color[i:i + 2], 16) / 255
        channels.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def ratio(fg, bg):
    hi, lo = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def test_tokens_are_hex_and_known_font():
    theme = json.loads(DATA.read_text())["theme"]
    assert theme["font"] == "tahoma"
    for key, value in theme.items():
        if key != "font":
            assert re.fullmatch(r"#[0-9a-f]{6}", value), key


def test_foray_pairs_meet_aa():
    theme = json.loads(DATA.read_text())["theme"]
    for fg, bg in PAIRS:
        assert ratio(theme[fg], theme[bg]) >= 4.5, (fg, bg)
