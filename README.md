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

## Contributing
1. Fork the repository and create a feature branch.
2. Make your changes and update `sitemap.xml` using `ruby sitemap.rb`.
3. Run `bundle exec rspec` to ensure tests pass.
4. Submit a pull request describing your changes.

## Deployment
1. Regenerate the sitemap and run the tests.
2. Commit and push to the `main` branch.
3. Copy the repository contents to the production web server (e.g., with `rsync` or `scp`).
