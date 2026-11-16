# Community Engine host app for nlmushrooms.ca

Fresh Rails 8.1 app running the Community Engine gem (`better_together`), the dedicated host app of Scenario A in
`docs/runbooks/ce-static-site-migration-dedicated-host.md` (management-tool). Target: `ce.nlmushrooms.ca`.

## Layout

This branch is the Rails app only, at the repository root. The static site lives on `main` (Netlify) and
`upgrade/ce-shared`, and is not on this branch. Dokku builds the root `Dockerfile`; no `build-dir` setting is needed
(Dokku 0.38.34 pinned in `bin/prod/host-setup.versions`). `scripts/ce/` holds the migration tooling (seed packet
generator, redirect map, crawl parity); it reads a checkout of the static site given with `--site-root`.

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

1. `rails new nlmushrooms.ca -d postgresql -A -T --skip-kamal --skip-solid --skip-jbuilder --skip-git --skip-docker --skip-rubocop --skip-ci --skip-bundle` (Rails 8.1.4.1, Ruby 3.4.12, image `ce-fresh-rails:8.1`).
2. Gem pinned by `ref:` to community-engine-rails `1c26c4678de17d95936efea0fed424c7e69d99e1`, forks `pundit-resources` and `storext`, lockfile platforms `x86_64-linux` and `aarch64-linux`.
3. `mkdir -p app/assets/config && touch app/assets/config/manifest.js`, then `bin/rails g better_together:install` (defaults, gem migrations).
4. Hand edits listed in the hardening commit: `app/assets/images` and `app/javascript` placeholders (the installer's manifest links need them), health route, production config, Sidekiq, Sentry, Dockerfile, CI.
5. `bin/rails g rspec:install`, then `bin/rails db:create db:migrate` (398 gem migrations, `db/schema.rb` generated, no `db/migrate` directory).

## Seed packet check (runbook section 3 step 5)

```bash
python3 scripts/ce/seed_packet.py --site-root <site checkout> --out tmp/ce/nlm-site --blobs hardlink
# (site checkout = a worktree of origin/main with git lfs pull done)
SEED_PACKET_DIR=$PWD/tmp/ce bin/dc-run bash -c \
  'PACKET=/packet/nlm-site PLATFORM=<scratch platform identifier> bin/rails better_together:seeds:plan'
```

`redirect_map.py` and `crawl_parity.py` take the same `--site-root`.

At gem `1c26c4678` the plan reports errors, not zero: the gem's seed registry does not yet model the fields the
generator emits (see the PR description for counts). Nothing is planted until this reaches zero.

## Rules

- Never run `better_together:install:migrations`. `bin/check-engine-migrations` and the specs fail if a
  `db/migrate/*.better_together.rb` file appears.
- No secrets in the repo. `config/master.key`, credentials keys and `.env*` are ignored; production values come from
  Dokku config (see `app.json` for the names). The first deploy is `rails db:seed`, run once by a human (T3), then the
  setup wizard at `/en/w/setup_wizard`.
- `postdeploy` seeding is deliberately absent from `app.json`.
- Deploy only through CI green then `git push <dokku-remote> main` with owner confirmation. Do not deploy from this
  branch.
