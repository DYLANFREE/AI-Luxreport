#!/usr/bin/env ruby
# Publish the standalone short share from its authoritative content directory.

require "fileutils"
require "json"
require "pathname"
require "uri"

SCRIPT_DIR = Pathname.new(__dir__).realpath
SITE = SCRIPT_DIR.parent
WORKSPACE = SITE.parent
SOURCE = WORKSPACE.join("与AI同行/09_AI泡沫全景/01_成果_暂定完成/短分享_等待过度预期破裂")
OUTPUT_NAME = "waiting-for-overreaction"
OUTPUT = SITE.join(OUTPUT_NAME)
STAGING = SITE.join(".#{OUTPUT_NAME}.staging")

FILES = %w[index.html history-browser.js].freeze

def local_url?(url)
  return false if url.nil? || url.empty?
  return false if url.start_with?("#", "data:", "mailto:", "tel:", "javascript:")
  return false if url.match?(%r{\A(?:https?:)?//}i)

  true
end

def clean_url_path(url)
  path = url.split(/[?#]/, 2).first.to_s
  URI.decode_www_form_component(path)
end

def validate_local_refs!(html, root)
  refs = []
  html.scan(/(?:src|href)=["']([^"']+)["']/i) { |match| refs << match[0] }
  html.scan(/url\(([^)]+)\)/i) do |match|
    refs << match[0].strip.gsub(/\A['"]|['"]\z/, "")
  end

  local_refs = refs.uniq.select { |ref| local_url?(ref) }
  escaped = []
  missing = []

  local_refs.each do |ref|
    clean = clean_url_path(ref)
    next if clean.empty?

    path = Pathname.new(clean)
    if path.absolute? || path.each_filename.any? { |part| part == ".." }
      escaped << ref
      next
    end

    missing << ref unless root.join(path).file?
  end

  errors = []
  errors << "escaped local refs: #{escaped.join(', ')}" unless escaped.empty?
  errors << "missing local refs: #{missing.join(', ')}" unless missing.empty?
  raise errors.join("\n") unless errors.empty?

  { refs: refs.length, local_refs: local_refs.length }
end

def validate_script_assets!(script, root)
  refs = script.scan(/["'](assets\/[^"']+)["']/).flatten.uniq
  escaped = refs.select { |ref| Pathname.new(ref).each_filename.any? { |part| part == ".." } }
  missing = refs.reject { |ref| root.join(ref).file? }

  errors = []
  errors << "escaped script assets: #{escaped.join(', ')}" unless escaped.empty?
  errors << "missing script assets: #{missing.join(', ')}" unless missing.empty?
  raise errors.join("\n") unless errors.empty?

  { local_assets: refs.length }
end

raise "Missing source directory: #{SOURCE}" unless SOURCE.directory?
FILES.each do |name|
  raise "Missing source file: #{SOURCE.join(name)}" unless SOURCE.join(name).file?
end
raise "Missing source assets: #{SOURCE.join('assets')}" unless SOURCE.join("assets").directory?
raise "Unsafe output path" unless OUTPUT.parent.realpath == SITE.realpath && OUTPUT.basename.to_s == OUTPUT_NAME

FileUtils.rm_rf(STAGING)
FileUtils.mkdir_p(STAGING)
FILES.each { |name| FileUtils.cp(SOURCE.join(name), STAGING.join(name)) }
FileUtils.cp_r(SOURCE.join("assets"), STAGING.join("assets"))

html = STAGING.join("index.html").read(encoding: "UTF-8")
script = STAGING.join("history-browser.js").read(encoding: "UTF-8")
raise "Published files contain an absolute local path" if [html, script].any? { |content| content.include?("file:") || content.include?("/Users/") }

validation = validate_local_refs!(html, STAGING)
script_validation = validate_script_assets!(script, STAGING)
asset_count = STAGING.join("assets").children.count(&:file?)

FileUtils.rm_rf(OUTPUT)
FileUtils.mv(STAGING, OUTPUT)

puts JSON.pretty_generate(
  source: SOURCE.relative_path_from(WORKSPACE).to_s,
  output: OUTPUT.relative_path_from(SITE).to_s,
  files: FILES,
  assets: asset_count,
  validation: validation,
  script_validation: script_validation
)
