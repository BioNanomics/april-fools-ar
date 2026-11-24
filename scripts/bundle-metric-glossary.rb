#!/usr/bin/env ruby
# Markdown is the source of truth. Generate the offline page and copy only the
# diagrams it references into the app bundle (or a simulator test bundle).
require 'cgi'
require 'fileutils'
require 'optparse'
require 'rdoc'
require 'rdoc/markdown'
require 'rdoc/markup/to_html'

options = {}
OptionParser.new do |parser|
  parser.on('--output DIR', 'Destination MetricGlossary directory') { |value| options[:output] = value }
end.parse!
abort 'Usage: ruby scripts/bundle-metric-glossary.rb --output DIR' unless options[:output]

root = File.expand_path('..', __dir__)
docs = File.join(root, 'docs')
markdown = File.read(File.join(docs, 'tag-metric-glossary.md'))
anchors = markdown.scan(/<a id="([a-z0-9-]+)"><\/a>/).flatten
abort 'Glossary requires explicit section anchors.' if anchors.empty?
abort 'Glossary has duplicate section anchors.' unless anchors.uniq == anchors
markdown.scan(/\]\(#([a-z0-9-]+)\)/).flatten.each do |anchor|
  abort "Missing glossary section: #{anchor}" unless anchors.include?(anchor)
end

assets = {}
# RDoc discards Markdown image alt text. Retain it separately and add it back to
# the generated image tags so VoiceOver receives the source descriptions.
markdown.scan(/!\[([^\]]*)\]\(([^\s)]+)\)/).each do |alt, relative|
  unless relative.match?(%r{\Adiagrams/[a-z0-9-]+\.svg\z}) && File.file?(File.join(docs, relative))
    abort "Missing or unsupported glossary diagram: #{relative}"
  end
  abort "Glossary diagram needs alt text: #{relative}" if alt.strip.empty?
  assets[relative] = alt
end

rdoc_options = RDoc::Options.new
rdoc_options.pipe = true
rdoc_options.output_decoration = false
body = RDoc::Markdown.parse(markdown).accept(RDoc::Markup::ToHtml.new(rdoc_options))
body = body.gsub(/<h([1-6])>/, '<h\1 tabindex="-1">')
body = body.gsub(/<img src="([^"]+)"\s*\/?\s*>/) do
  relative = Regexp.last_match(1)
  alt = assets.fetch(relative) { abort "Unrecognized glossary image: #{relative}" }
  %(<img src="#{CGI.escapeHTML(relative)}" alt="#{CGI.escapeHTML(alt)}">)
end
expected_images = markdown.scan(/!\[([^\]]*)\]\(([^\s)]+)\)/).count
unless body.scan(/<img\s/).count == expected_images
  abort 'Glossary renderer did not preserve all Markdown images.'
end

html = <<~HTML
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'">
    <title>Measurement glossary</title>
    <style>
      :root { color-scheme: light dark; font: -apple-system-body; }
      body { margin: 0; color: #182331; background: #fff; line-height: 1.55; }
      main { max-width: 46rem; margin: auto; padding: 20px max(20px, env(safe-area-inset-right)) 60px max(20px, env(safe-area-inset-left)); overflow-wrap: anywhere; }
      h1 { font-size: 1.8rem; line-height: 1.2; }
      h2 { margin-top: 2.2rem; font-size: 1.35rem; line-height: 1.3; }
      h3 { margin-top: 1.6rem; font-size: 1.1rem; }
      h1, h2, h3 { outline: none; }
      a { color: #005dbe; text-decoration: underline; text-underline-offset: .15em; }
      a[id] { display: block; scroll-margin-top: 16px; }
      a:focus-visible { outline: 3px solid #2784eb; border-radius: 2px; }
      p, ul, ol { margin-top: .8rem; margin-bottom: .8rem; }
      li { margin-bottom: .35rem; }
      img { display: block; width: 100%; height: auto; margin: 1.2rem 0; border-radius: 12px; background: #f5f8fc; }
      code { font-family: ui-monospace, monospace; font-size: .9em; padding: .1em .25em; border-radius: .2em; background: #eef2f6; }
      pre { padding: 12px; overflow-x: auto; border-radius: 8px; background: #eef2f6; }
      pre code { padding: 0; }
      blockquote { margin-left: 0; padding-left: 16px; border-left: 3px solid #8ba4bb; }
      @media (prefers-color-scheme: dark) {
        body { color: #e9eef5; background: #101923; }
        a { color: #88c6ff; }
        code, pre { background: #243243; }
      }
    </style>
  </head>
  <body><main id="top">#{body}</main></body>
  </html>
HTML

output = File.expand_path(options.fetch(:output))
FileUtils.mkdir_p(File.join(output, 'diagrams'))
File.write(File.join(output, 'index.html'), html)
assets.each_key do |relative|
  FileUtils.cp(File.join(docs, relative), File.join(output, relative))
end
Dir.glob(File.join(output, 'diagrams', '*.svg')).each do |path|
  FileUtils.rm(path) unless assets.include?("diagrams/#{File.basename(path)}")
end
puts "Bundled metric glossary: #{anchors.count} definitions, #{assets.count} diagrams."
