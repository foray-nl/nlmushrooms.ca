#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the manifest entries that still need action (status missing or located). Read-only.
#   ruby scripts/missing_files_report.rb
require 'yaml'

manifest = YAML.safe_load_file(File.expand_path('../manifests/missing-files.yml', __dir__))
todo = manifest.fetch('files').select { |e| %w[missing located].include?(e['status']) }
puts "#{todo.size} file(s) to locate/upload (of #{manifest['files'].size} entries)"
todo.each do |e|
  puts "- #{e['path']} [#{e['status']}] referenced by #{Array(e['referenced_by']).join(', ')}"
  puts "    look in: #{Array(e['possible_locations']).join('; ')}"
end
