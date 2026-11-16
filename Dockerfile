# Production image, built by Dokku from the repository root. Local dev uses Dockerfile.dev.

# Stage 1: libxml2 built from source with a pinned checksum (CVE fix, do not drop this stage).
FROM ruby:3.4.12-slim AS libxml2-bin

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential wget tar gcc pkg-config python3-dev xz-utils ca-certificates \
  && wget https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.4.tar.xz -O /tmp/libxml2.tar.xz \
  && echo "98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821  /tmp/libxml2.tar.xz" | sha256sum -c - \
  && mkdir -p /tmp/libxml2 \
  && tar -xf /tmp/libxml2.tar.xz -C /tmp/libxml2 --strip-components=1

WORKDIR /tmp/libxml2

RUN ./configure --prefix=/opt/libxml2 PYTHON=/usr/bin/python3 \
  && make \
  && make install \
  && rm -rf /tmp/libxml2 /tmp/libxml2.tar.xz

# Stage 2: gems and assets
FROM ruby:3.4.12-slim AS builder

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    build-essential git libpq-dev libssl-dev libyaml-dev libvips42 ca-certificates pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /bt

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' \
  && bundle config set deployment true \
  && bundle config set path 'vendor/bundle' \
  && bundle install --jobs 4 --retry 3

COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production bundle exec rake assets:precompile \
  && rm -rf /bt/tmp/cache /bt/log/* /bt/spec /bt/test /bt/node_modules

# Stage 3: runtime
FROM ruby:3.4.12-slim AS app-host

RUN apt-get update -qq \
  && apt-get upgrade -y --no-install-recommends \
  && apt-get install -y --no-install-recommends libpq5 libvips42 libyaml-0-2 libssl3 ca-certificates curl tzdata \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --uid 1000 --create-home rails

COPY --from=libxml2-bin /opt/libxml2 /opt/libxml2

ENV LD_LIBRARY_PATH=/opt/libxml2/lib \
    PKG_CONFIG_PATH=/opt/libxml2/lib/pkgconfig \
    BUNDLE_PATH=/bt/vendor/bundle \
    BUNDLE_APP_CONFIG=/bt/vendor/bundle \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT=development:test \
    RAILS_ENV=production \
    RACK_ENV=production

WORKDIR /bt
COPY --from=builder --chown=rails:rails /bt /bt
RUN mkdir -p tmp/pids log storage && chown -R rails:rails tmp log storage

USER rails
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
