#!/usr/bin/env bash
set -euo pipefail

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev libsqlite3-dev curl git

# Install rbenv if not present
if [ ! -d "$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git ~/.rbenv
  cd ~/.rbenv && src/configure && make -C src
else
  cd ~/.rbenv && git pull
fi

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"

# Install ruby-build plugin
if [ ! -d "$HOME/.rbenv/plugins/ruby-build" ]; then
  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
else
  cd ~/.rbenv/plugins/ruby-build && git pull
fi

# Install latest stable Ruby
latest_ruby=$(rbenv install -l | grep -v - | tail -1 | tr -d ' ')
rbenv install -s "$latest_ruby"
rbenv global "$latest_ruby"

# Install bundler and project gems
gem install bundler --no-document
bundle install
