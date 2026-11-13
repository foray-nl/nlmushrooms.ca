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
