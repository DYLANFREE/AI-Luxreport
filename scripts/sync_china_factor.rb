#!/usr/bin/env ruby
# Sync the China factor report into this static publish directory.

require "fileutils"
require "json"
require "pathname"
require "uri"

SCRIPT_DIR = Pathname.new(__dir__).realpath
SITE = SCRIPT_DIR.parent
WORKSPACE = SITE.parent
SOURCE = WORKSPACE.join("与AI同行/研究/09_AI泡沫全景/中国因素/中国因素_问题推导链.html")
SOURCE_DIR = SOURCE.dirname
INDEX = SITE.join("index.html")
ASSETS = SITE.join("assets")

def local_url?(url)
  return false if url.nil? || url.empty?
  return false if url.start_with?("#", "data:", "mailto:", "tel:", "javascript:")
  return false if url.match?(%r{\A(?:https?:)?//}i)

  true
end

def split_url(url)
  path, tail = url.split(/([?#].*)/, 2)
  [URI.decode_www_form_component(path.to_s), tail.to_s]
end

def asset_name(path)
  File.basename(path).gsub(/[^\p{Alnum}._-]+/u, "_")
end

def rewrite_local_refs(html)
  copied = []
  rewritten = html.gsub(/((?:src|href)=["'])([^"']+)(["'])/i) do
    prefix = Regexp.last_match(1)
    url = Regexp.last_match(2)
    suffix = Regexp.last_match(3)
    next Regexp.last_match(0) unless local_url?(url)

    clean, tail = split_url(url)
    next Regexp.last_match(0) if clean.empty? || clean.start_with?("/")

    source_path = SOURCE_DIR.join(clean).cleanpath
    next Regexp.last_match(0) unless source_path.file?

    dest_rel = File.join("assets", asset_name(clean))
    dest_path = SITE.join(dest_rel)
    FileUtils.mkdir_p(dest_path.dirname)
    FileUtils.cp(source_path, dest_path)
    copied << dest_rel
    "#{prefix}#{dest_rel}#{tail}#{suffix}"
  end

  rewritten = rewritten.gsub(/url\(([^)]+)\)/i) do
    raw = Regexp.last_match(1).strip
    quote = raw.start_with?('"', "'") ? raw[0] : ""
    url = raw.gsub(/\A['"]|['"]\z/, "")
    next Regexp.last_match(0) unless local_url?(url)

    clean, tail = split_url(url)
    next Regexp.last_match(0) if clean.empty? || clean.start_with?("/")

    source_path = SOURCE_DIR.join(clean).cleanpath
    next Regexp.last_match(0) unless source_path.file?

    dest_rel = File.join("assets", asset_name(clean))
    dest_path = SITE.join(dest_rel)
    FileUtils.mkdir_p(dest_path.dirname)
    FileUtils.cp(source_path, dest_path)
    copied << dest_rel
    wrapped = quote.empty? ? "#{dest_rel}#{tail}" : "#{quote}#{dest_rel}#{tail}#{quote}"
    "url(#{wrapped})"
  end

  [rewritten, copied.uniq.sort]
end

def validate!(html)
  refs = []
  html.scan(/(?:src|href)=["']([^"']+)["']/i) { |m| refs << m[0] }
  html.scan(/url\(([^)]+)\)/i) { |m| refs << m[0].strip.gsub(/\A['"]|['"]\z/, "") }
  local_refs = refs.uniq.select { |ref| local_url?(ref) }
  escaped = local_refs.select { |ref| ref.start_with?("../", "/") }
  missing = local_refs.reject do |ref|
    clean, = split_url(ref)
    SITE.join(clean).file?
  end

  errors = []
  errors << "Escaped local refs: #{escaped.join(', ')}" unless escaped.empty?
  errors << "Missing local refs: #{missing.join(', ')}" unless missing.empty?
  raise errors.join("\n") unless errors.empty?

  { refs: refs.length, local_refs: local_refs.length }
end

source_html = File.read(SOURCE, encoding: "UTF-8")
site_html, copied = rewrite_local_refs(source_html)
File.write(INDEX, site_html, mode: "w", encoding: "UTF-8")
validation = validate!(site_html)

puts JSON.pretty_generate(
  source: SOURCE.relative_path_from(WORKSPACE).to_s,
  index: INDEX.relative_path_from(WORKSPACE).to_s,
  bytes: site_html.bytesize,
  copied: copied,
  validation: validation
)
