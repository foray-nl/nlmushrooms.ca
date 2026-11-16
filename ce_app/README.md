# ce_app: Community Engine host app for nlmushrooms.ca

Fresh Rails 8.1 app running the Community Engine gem (`better_together`), the dedicated host app of Scenario A in
`docs/runbooks/ce-static-site-migration-dedicated-host.md` (management-tool). Target: `ce.nlmushrooms.ca`.

## Why a subdirectory

The static site stays deployable from `main` and its files, Gemfile, `spec/`, `scripts/ce/` seed packet tooling and
`layout/` data are inputs to the packet generator. A Rails app at the repository root would collide on `Gemfile`,
`spec/`, `public/` and `images/`. Dokku builds from a subdirectory with
`dokku builder:set <app> build-dir ce_app` (Dokku 0.38.34 pinned in `bin/prod/host-setup.versions`); the Dockerfile,
Procfile and app.json live in this directory, which is the build context. Setting it on the server is a T3 step.

## Local harness

```bash
bin/dc build app
bin/dc-run bundle install
bin/dc-run bin/rails db:create db:migrate
bin/dc-run bundle exec rspec          # RAILS_ENV=test
bin/dc-run bundle exec rubocop --parallel
```

Everything runs in the compose stack (PostGIS, Redis). Nothing here touches a server.

## Build log (each step is one commit)

1. `rails new ce_app -d postgresql -A -T --skip-kamal --skip-solid --skip-jbuilder --skip-git --skip-docker --skip-rubocop --skip-ci --skip-bundle` (Rails 8.1.4.1, Ruby 3.4.12, image `ce-fresh-rails:8.1`).
2. Gem pinned by `ref:` to community-engine-rails `1c26c4678de17d95936efea0fed424c7e69d99e1`, forks `pundit-resources` and `storext`, lockfile platforms `x86_64-linux` and `aarch64-linux`.
3. `mkdir -p app/assets/config && touch app/assets/config/manifest.js`, then `bin/rails g better_together:install` (defaults, gem migrations).
4. Hand edits listed in the hardening commit: `app/assets/images` and `app/javascript` placeholders (the installer's manifest links need them), health route, production config, Sidekiq, Sentry, Dockerfile, CI.
5. `bin/rails g rspec:install`, then `bin/rails db:create db:migrate` (398 gem migrations, `db/schema.rb` generated, no `db/migrate` directory).

## Rules

- Never run `better_together:install:migrations`. `bin/check-engine-migrations` and the specs fail if a
  `db/migrate/*.better_together.rb` file appears.
- No secrets in the repo. `config/master.key`, credentials keys and `.env*` are ignored; production values come from
  Dokku config (see `app.json` for the names). The first deploy is `rails db:seed`, run once by a human (T3), then the
  setup wizard at `/en/w/setup_wizard`.
- `postdeploy` seeding is deliberately absent from `app.json`.
- Deploy only through CI green then `git push <dokku-remote> main` with owner confirmation. Do not deploy from this
  branch.
