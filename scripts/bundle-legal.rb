#!/usr/bin/env ruby
require 'json'

root = File.expand_path('..', __dir__)
documents = {
  'privacy' => 'docs/PRIVACY.md',
  'license' => 'LICENSE',
  'thirdPartyNotices' => 'THIRD_PARTY_NOTICES.md'
}.transform_values do |relative|
  File.read(File.join(root, relative))
      .gsub(/^\#{1,6} /, '')
      .gsub(/^```[^\n]*\n/, '')
      .gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1 (\2)')
      .gsub('**', '')
      .gsub(/`([^`]+)`/, '\1')
      .strip
end
path = File.join(root, 'legal-documents.json')
contents = JSON.pretty_generate(documents) + "\n"
if ARGV.include?('--check')
  abort 'Bundled legal documents are stale. Run ruby scripts/bundle-legal.rb.' unless File.exist?(path) && File.read(path) == contents
else
  File.write(path, contents) unless File.exist?(path) && File.read(path) == contents
end
