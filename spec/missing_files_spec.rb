# frozen_string_literal: true

require 'yaml'
require 'support/internal_links'

# Report-only guard for broken internal references. It never edits files: a missing target must either be fixed
# or listed in manifests/missing-files.yml, and the manifest must stay honest about what is still missing.
RSpec.describe 'Missing files manifest' do
  let(:manifest) { YAML.safe_load_file(File.join(InternalLinks::ROOT, 'manifests', 'missing-files.yml')) }
  let(:ignored) { manifest.fetch('ignore_sources').map { |e| e.fetch('path') } }
  let(:entries) { manifest.fetch('files').to_h { |e| [e.fetch('path'), e] } }
  let(:missing) { InternalLinks.missing(ignore_sources: ignored) }
  let(:on_disk) { ->(path) { File.exist?(File.join(InternalLinks::ROOT, path)) } }

  it 'lists every referenced path that is not in the repository' do
    unlisted = missing.reject { |path, _| entries.key?(path) }
    expect(unlisted).to be_empty,
                        "Unlisted missing targets (fix the link or add to manifests/missing-files.yml):\n" +
                        unlisted.map { |path, pages| "  #{path} <- #{pages.join(', ')}" }.join("\n")
  end

  it 'only marks entries as missing while they are still missing' do
    found = entries.select { |path, e| e['status'] == 'missing' && on_disk.call(path) }.keys
    expect(found).to be_empty, "Now present, update status to located/uploaded: #{found.join(', ')}"
  end

  it 'has the file in the repository for every uploaded entry' do
    absent = entries.select { |path, e| e['status'] == 'uploaded' && !on_disk.call(path) }.keys
    expect(absent).to be_empty, "Marked uploaded but absent: #{absent.join(', ')}"
  end

  it 'uses a known status and records where each page is referenced' do
    statuses = %w[missing located uploaded superseded]
    bad = entries.reject { |_, e| statuses.include?(e['status']) && Array(e['referenced_by']).any? }.keys
    expect(bad).to be_empty
  end
end
