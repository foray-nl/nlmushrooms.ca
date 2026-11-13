from foray_ce import site


def test_paths_nest_by_parent_and_skip_home(site_root):
    s = site.Site(site_root)
    assert s.path("index.html") == ""
    assert s.path("foray_2025.html") == "past-forays/foray-2025"
    assert s.path("omphalina_2021.html") == "omphalina/omphalina-2021"


def test_slug_overrides_apply(site_root):
    with open(site_root + "/layout/ce-slugs.yml", "w") as handle:
        handle.write("omphalina_2021.html: volume-12\n")
    assert site.Site(site_root).path("omphalina_2021.html") == "omphalina/volume-12"


def test_old_paths_cover_extensionless_and_home(site_root):
    s = site.Site(site_root)
    assert s.old_paths("past_forays.html") == ["/past_forays.html", "/past_forays"]
    assert s.old_paths("index.html") == ["/", "/index.html", "/index"]


def test_url_forms_encode_spaces():
    assert site.url_forms("/a b.pdf") == ["/a b.pdf", "/a%20b.pdf"]
    assert site.url_forms("/a.pdf") == ["/a.pdf"]


def test_public_pdfs_skip_archive(site_root):
    pdfs = site.public_pdfs(site_root)
    assert "archive/forms/old.pdf" not in pdfs
    assert "anncum_1.pdf" in pdfs and len(pdfs) == 4


def test_site_images_only_image_dirs(site_root):
    assert site.site_images(site_root) == ["_wp_generated/t1.png", "_wp_generated/t3.png", "images/poster.png",
                                           "images/share/default.jpg"]


def test_upload_slugs_resolve_collisions():
    slugs = site.upload_slugs(["a/x.pdf", "b/x.pdf", "c/x.pdf"], {})
    assert len(set(slugs.values())) == 3
    assert slugs["a/x.pdf"] == "x"


def test_issue_label_uses_roman_numerals():
    assert site.issue_label(12, 3, 2021) == "Omphalina Volume XII, No. 3 (2021)"
    assert site.roman(9) == "ix"


def test_lfs_pointer_detection(tmp_path):
    p = tmp_path / "x.pdf"
    p.write_bytes(b"version https://git-lfs.github.com/spec/v1\noid sha256:1\n")
    assert site.is_lfs_pointer(str(p))
    p.write_bytes(b"%PDF-1.4")
    assert not site.is_lfs_pointer(str(p))
