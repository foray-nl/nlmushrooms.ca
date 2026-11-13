import os
import sys
import textwrap

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def write(root, rel, text="", binary=None):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if binary is not None:
        with open(path, "wb") as handle:
            handle.write(binary)
    else:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(textwrap.dedent(text))
    return path


@pytest.fixture
def site_root(tmp_path):
    """A tiny but complete foray-shaped tree: four pages, one foray, one volume, PDFs and images."""
    root = str(tmp_path / "site")
    write(root, "layout/site-nav.yml", """
        site:
          name: Foray Test
          url: https://example.test
          locale: en_CA
          organization: {legal_name: Test Inc., email: a@example.test, telephone: "+1-709-000-0000", locality: Torbay, region: NL, country: CA}
          image: images/share/default.jpg
          image_alt: Logo
        pages:
          - {file: index.html, name: Home, description: Home page}
          - {file: past_forays.html, name: Past Forays, parent: index.html, description: Past, subnav: true}
          - {file: foray_2025.html, name: Foray 2025, parent: past_forays.html, description: F25, image: images/share/f25.jpg, image_alt: Poster}
          - {file: omphalina.html, name: Omphalina, parent: index.html, description: Omph}
          - {file: omphalina_2021.html, name: Vol 12, parent: omphalina.html, description: V12}
    """)
    write(root, "layout/forays.yml", """
        - {year: 2025, name: Foray 2025, venue: Pinchgut Lake, area: West, start: 2025-09-26, end: 2025-09-28, page: foray_2025.html, report: "foray_reports/2025 report.pdf", art: {file: images/poster.png}, art_alt: Poster}
        - {year: 2021, name: Foray 2021, status: cancelled, note: unsure}
    """)
    write(root, "layout/omphalina.yml", """
        - volume: 12
          year: 2021
          page: omphalina_2021.html
          issues:
            - {issue: 1, pdf: "omphaline/Omphalina XII-1.pdf", thumb: _wp_generated/t1.png}
            - {issue: 3, pdf: "omphaline/Omphalina_XII-3.pdf", thumb: _wp_generated/t3.png}
    """)
    write(root, "layout/socials.yml", """
        - {platform: Facebook, icon: fa-facebook, handle: ForayNL, url: "https://www.facebook.com/ForayNL"}
        - {platform: Flickr, icon: fa-flickr, handle: foray_nl, url: "https://www.flickr.com/photos/foray_nl/"}
    """)
    write(root, "layout/footer.yml", "tagline: Forays since 2003.\nexplore: [past_forays.html]\ninvolved: []\nlegal: []\n")
    page = """<html><body><main class="page"><nav class="page-breadcrumb"><ol></ol></nav>
        <div class="page-body"><section class="content"><h1>{n}</h1><p>Text</p>{extra}</section></div></main></body></html>"""
    for name, extra in (("index", ""), ("past_forays", "<table><tr><td>x</td></tr></table>"), ("foray_2025", ""),
                        ("omphalina", ""), ("omphalina_2021", '<a href="omphaline/Omphalina XII-1.pdf">PDF</a>')):
        write(root, f"{name}.html", page.format(n=name, extra=extra))
    for rel, data in (("foray_reports/2025 report.pdf", b"%PDF-1.4 a"), ("omphaline/Omphalina XII-1.pdf", b"%PDF-1.4 b"),
                      ("omphaline/Omphalina_XII-3.pdf", b"%PDF-1.4 c"), ("archive/forms/old.pdf", b"%PDF-1.4 d"),
                      ("anncum_1.pdf", b"%PDF-1.4 e"), ("images/poster.png", b"png1"), ("_wp_generated/t1.png", b"png2"),
                      ("_wp_generated/t3.png", b"png3"), ("images/share/default.jpg", b"jpg"), ("images/share/f25.jpg", b"jpg2")):
        write(root, rel, binary=data)
    return root
