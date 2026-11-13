from foray_ce import inventory, site


def test_build_titles_slugs_and_kinds(site_root):
    uploads = {u["path"]: u for u in inventory.build(site.Site(site_root))}
    assert uploads["omphaline/Omphalina_XII-3.pdf"]["slug"] == "omphalina-xii-3"
    assert uploads["omphaline/Omphalina XII-1.pdf"]["title"] == "Omphalina Volume XII, No. 1 (2021)"
    assert uploads["foray_reports/2025 report.pdf"]["slug"] == "foray-report-2025"
    assert uploads["anncum_1.pdf"]["title"] == "anncum 1"
    assert uploads["images/poster.png"]["kind"] == "image" and uploads["images/poster.png"]["alt"] == "Poster"
    assert "archive/forms/old.pdf" not in uploads


def test_shared_report_gets_one_upload(site_root):
    s = site.Site(site_root)
    s.forays.append({"year": 2026, "name": "Foray 2026", "report": "foray_reports/2025 report.pdf"})
    u = {x["path"]: x for x in inventory.build(s)}["foray_reports/2025 report.pdf"]
    assert u["slug"] == "foray-report-2025-2026" and u["title"] == "Foray 2025 and 2026 report"


def test_status_and_hash(site_root):
    with open(site_root + "/anncum_1.pdf", "wb") as handle:
        handle.write(b"version https://git-lfs.github.com/spec/v1\noid sha256:aa\nsize 9\n")
    uploads = {u["path"]: u for u in inventory.build(site.Site(site_root))}
    assert uploads["anncum_1.pdf"]["status"] == "lfs_pointer" and uploads["anncum_1.pdf"]["sha256"] is None
    assert len(uploads["images/poster.png"]["sha256"]) == 64


def test_no_hash_mode_and_summary(site_root):
    uploads = inventory.build(site.Site(site_root), hash_files=False)
    assert all(u["sha256"] is None for u in uploads)
    summary = inventory.summarize(uploads)
    assert summary["by_kind"] == {"document": 4, "image": 5} and summary["total"] == 9
