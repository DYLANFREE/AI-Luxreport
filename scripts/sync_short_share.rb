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
SERIES_TITLE = "AI 产业与投资研究"

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

def decorate_series(html)
  html = html.sub(/<title>(.*?)<\/title>/im) do
    original = Regexp.last_match(1)
    title = original.include?(SERIES_TITLE) ? original : "#{original}｜#{SERIES_TITLE}"
    "<title>#{title}</title>"
  end
  html = html.sub(/<\/head>/i, "  <link rel=\"stylesheet\" href=\"../assets/research-series.css\">\n  <link rel=\"icon\" href=\"../assets/favicon.svg\" type=\"image/svg+xml\">\n</head>") unless html.include?("research-series.css")
  header = <<~HTML
    <header class="research-series-bar">
      <a class="research-series-link" href="../index.html" aria-label="返回 AI 产业与投资研究首页">
        <span class="research-series-mark" aria-hidden="true"></span>
        <span class="research-series-name">#{SERIES_TITLE}</span>
        <span class="research-series-home">研究首页 <span aria-hidden="true">→</span></span>
      </a>
    </header>
  HTML
  html.sub(/<body([^>]*)>/i) do
    attributes = Regexp.last_match(1)
    if attributes.match?(/\bclass=["']/i)
      attributes = attributes.sub(/\bclass=(["'])(.*?)\1/i) do
        quote = Regexp.last_match(1)
        classes = Regexp.last_match(2)
        %(class=#{quote}#{classes} research-series-page research-series-page--fixed-nav#{quote})
      end
    else
      attributes = %(#{attributes} class="research-series-page research-series-page--fixed-nav")
    end
    "<body#{attributes}>\n#{header}"
  end
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
    allowed_parent_ref = {
      "../index.html" => root.parent.join("index.html"),
      "../assets/research-series.css" => root.parent.join("assets/research-series.css"),
      "../assets/favicon.svg" => root.parent.join("assets/favicon.svg")
    }[clean]
    if allowed_parent_ref
      missing << ref unless allowed_parent_ref.file?
      next
    end

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

html = decorate_series(STAGING.join("index.html").read(encoding: "UTF-8"))
STAGING.join("index.html").write(html, mode: "w", encoding: "UTF-8")
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
