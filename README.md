# nlmushrooms.ca

Static website for the Newfoundland and Labrador Mycological Society.

## Repository Layout
- `index.html` and other `*.html` files: static pages for the site.
- `images/`, `articles/`, `foray_reports/`, `species_lists/`, `science/`: content directories referenced by the pages.
- `sitemap.rb`: script to generate `sitemap.xml` and `sitemap.txt`.
- `spec/`: RSpec tests for basic navigation and membership pages.

## Serving Locally
Use Ruby's built‑in web server to view the site:

```bash
ruby -run -e httpd . -p 8000
```

Then open <http://localhost:8000/> in a browser.

## Sitemap Generation
Regenerate `sitemap.xml` and `sitemap.txt` after making changes to the site:

```bash
ruby sitemap.rb
```

## Running Tests
Install dependencies and run the RSpec suite:

```bash
bundle install
bundle exec rspec
```

## Before/after screenshots and accessibility (axe-core)
`spec/visual/pages_spec.rb` captures every HTML page (desktop 1440 px and mobile 430 px with viewport emulation, full page) and runs axe-core. It needs Chrome (Selenium Manager fetches it) and is opt-in:

```bash
git worktree add --detach tmp/baseline $(grep commit spec/baseline.yml | cut -d' ' -f2)   # once; add GIT_LFS_SKIP_SMUDGE=1 to skip PDFs
RUN_VISUAL=1 SITE_ROOT=tmp/baseline CAPTURE_LABEL=before bundle exec rspec spec/visual/pages_spec.rb
RUN_VISUAL=1 bundle exec rspec spec/visual/pages_spec.rb      # after, from the working tree
ruby scripts/compare_visual.rb   # tmp/visual/compare/index.html and tmp/visual/axe-summary.md
```
Output lives in `tmp/` (gitignored). Google Analytics and web fonts are blocked during capture so runs are repeatable.

## Missing files manifest
`manifests/missing-files.yml` lists files that pages reference but the repository does not contain (to be located and uploaded, or decided on link by link). `spec/missing_files_spec.rb` fails when a page references a missing path that is not listed, or when an entry's status is out of date. `ruby scripts/missing_files_report.rb` prints what still needs to be located. PDFs go in through Git LFS.

## Contributing
1. Fork the repository and create a feature branch.
2. Make your changes and update `sitemap.xml` using `ruby sitemap.rb`.
3. Run `bundle exec rspec` to ensure tests pass.
4. Submit a pull request describing your changes.

## Deployment
1. Regenerate the sitemap and run the tests.
2. Commit and push to the `main` branch.
3. Copy the repository contents to the production web server (e.g., with `rsync` or `scp`).

## Shared layout (header, nav, footer)

The shared regions live in `layout/partials/` (`head`, `header`, `nav`, `footer`). A page opts in by wrapping a
region in marker comments:

```html
<!-- layout:nav -->
<!-- /layout:nav -->
```

`ruby scripts/apply_layout.rb` fills every marked region from the partial (the nav link for the page itself gets
`class="active"`). `ruby scripts/apply_layout.rb --check` exits 1 if any page is out of date; `bundle exec rspec`
runs the same check, so CI fails on drift. Edit the partial, never the marked region in a page. Pages stay plain
static HTML, so Netlify serves them unchanged. Currently `foray_2025.html` and `foray_2026.html` use it; the legacy
pages adopt it as they are converted.

### Nav and Bootstrap

The nav partial uses the same Bootstrap 5 markup as the Community Engine gem (`navbar navbar-expand-lg navbar-dark`,
a `navbar-toggler`, and a `collapse navbar-collapse` list), so it collapses behind a toggler below 992 px and the
partial can move into a CE host app unchanged. Only the navbar, nav-link and collapse rules are vendored (full
Bootstrap would restyle every page), plus the unmodified JS bundle, all self-hosted in `assets/vendor/bootstrap/`.
`ruby scripts/vendor_bootstrap_nav.rb [VERSION]` regenerates them; site colours and spacing live in
`assets/styles/site.css`. `RUN_VISUAL=1 bundle exec rspec spec/visual/nav_spec.rb` checks the toggle and that nothing
scrolls sideways at 430, 992, 1200 and 1440 px.

### Social icons
Accounts live in `layout/socials.yml`; `apply_layout.rb` renders them as tooltipped icon links in the header (`{{social-links}}` in the header partial) and as an icon-plus-text list wherever a page has a `<!-- layout:social -->` region (Contacts). Icons are the Font Awesome Free brand glyphs, subset to the three in use (`assets/vendor/fontawesome/`, same `fa-brands fa-<name>` classes as Community Engine). To add a platform: add the glyph to the subset (`pyftsubset fa-brands-400.woff2 --unicodes=U+f09a,U+f16d,U+f16e,<new> --flavor=woff2 --output-file=assets/vendor/fontawesome/fa-brands-subset.woff2`), add its class to `fontawesome-social.css`, then add the account. Tooltips are Bootstrap's, started by `assets/scripts/site.js`; each link also has an `aria-label` ("Platform: handle (opens in a new tab)").

### Cache busting
`apply_layout.rb` appends `?v=<first 10 hex of the file's SHA-256>` to the local stylesheet and script URLs in the shared head, so a changed file is a new URL. `netlify.toml` caches those paths for a year (`immutable`), revalidates HTML on every load, and sets `no-cache` on unversioned static files. Run `ruby scripts/apply_layout.rb` after editing any CSS or JS; the layout spec fails if a reference is stale. Netlify also sends an ETag on every response.

### Before/after tables in PR bodies

Every PR that changes how a page looks shows the page before and after, desktop and mobile. After capturing
(see the harness section), `ruby scripts/pr_screenshots.rb stage --name <pr-name> --pages a,b --before <dir>
--after <dir>` copies the PNGs into `docs/screenshots/<pr-name>/` (never served by Netlify), and
`ruby scripts/pr_screenshots.rb table --name <pr-name> --sha <commit>` prints the markdown table with URLs pinned
to that commit, so the images survive branch deletion. A `--before` directory already under `docs/screenshots/`
(for example the committed baseline) is referenced in place.
