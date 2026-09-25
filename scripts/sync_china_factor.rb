#!/usr/bin/env ruby
# Sync the two-report static site.

require "fileutils"
require "json"
require "pathname"
require "uri"

SCRIPT_DIR = Pathname.new(__dir__).realpath
SITE = SCRIPT_DIR.parent
WORKSPACE = SITE.parent
ASSETS = SITE.join("assets")
SERIES_TITLE = "AI 产业与投资研究"

REPORTS = [
  {
    key: "ai",
    title: "AI供需研究",
    kicker: "Supply / Demand",
    description: "从训练成本、芯片产能、推理供给和真实需求出发，拆解 AI 繁荣是否具备持续基础。",
    source: WORKSPACE.join("与AI同行/研究/09_AI泡沫全景/AI供需研究_问题推导链.html"),
    output: "ai-supply-demand.html",
    fallback_dirs: [
      WORKSPACE.join("与AI同行/研究/09_AI泡沫全景/Q3Q4/研究笔记/assets")
    ]
  },
  {
    key: "china",
    title: "中国产业崛起之路",
    kicker: "China Factor",
    description: "从中国变量、国产模型、硬件约束和产业链重构出发，观察 NVIDIA 护城河受到的结构性冲击。",
    source: WORKSPACE.join("与AI同行/研究/09_AI泡沫全景/中国因素/中国因素_问题推导链.html"),
    output: "china-factor.html",
    fallback_dirs: []
  }
]

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

def asset_name(report_key, path)
  base = File.basename(path).gsub(/[^\p{Alnum}._-]+/u, "_")
  "#{report_key}-#{base}"
end

def resolve_source(clean, source_dir, fallback_dirs)
  direct = source_dir.join(clean).cleanpath
  return direct if direct.file?

  basename = File.basename(clean)
  fallback_dirs.each do |dir|
    candidate = dir.join(basename).cleanpath
    return candidate if candidate.file?
  end

  nil
end

def series_header(current: false)
  current_attribute = current ? ' aria-current="page"' : ""
  action = current ? "系列首页" : "研究首页"
  <<~HTML
    <header class="research-series-bar">
      <a class="research-series-link" href="index.html"#{current_attribute} aria-label="AI 产业与投资研究首页">
        <span class="research-series-mark" aria-hidden="true"></span>
        <span class="research-series-name">#{SERIES_TITLE}</span>
        <span class="research-series-home">#{action} <span aria-hidden="true">→</span></span>
      </a>
    </header>
  HTML
end

def decorate_report(html)
  html = html.sub(/<title>(.*?)<\/title>/im) do
    original = Regexp.last_match(1)
    title = original.include?(SERIES_TITLE) ? original : "#{original}｜#{SERIES_TITLE}"
    "<title>#{title}</title>"
  end

  unless html.include?('assets/research-series.css')
    html = html.sub(/<\/head>/i, "  <link rel=\"stylesheet\" href=\"assets/research-series.css\">\n  <link rel=\"icon\" href=\"assets/favicon.svg\" type=\"image/svg+xml\">\n</head>")
  end

  html.sub(/<body([^>]*)>/i) do
    attributes = Regexp.last_match(1)
    if attributes.match?(/\bclass=["']/i)
      attributes = attributes.sub(/\bclass=(["'])(.*?)\1/i) do
        quote = Regexp.last_match(1)
        classes = Regexp.last_match(2)
        %(class=#{quote}#{classes} research-series-page#{quote})
      end
    else
      attributes = %(#{attributes} class="research-series-page")
    end
    "<body#{attributes}>\n#{series_header}"
  end
end

def rewrite_local_refs(html, report)
  copied = []
  source_dir = report[:source].dirname
  fallback_dirs = report[:fallback_dirs]

  rewritten = html.gsub(/((?:src|href)=["'])([^"']+)(["'])/i) do
    prefix = Regexp.last_match(1)
    url = Regexp.last_match(2)
    suffix = Regexp.last_match(3)
    next Regexp.last_match(0) unless local_url?(url)

    clean, tail = split_url(url)
    next Regexp.last_match(0) if clean.empty? || clean.start_with?("/")

    source_path = resolve_source(clean, source_dir, fallback_dirs)
    next Regexp.last_match(0) unless source_path

    dest_rel = File.join("assets", asset_name(report[:key], source_path.basename.to_s))
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

    source_path = resolve_source(clean, source_dir, fallback_dirs)
    next Regexp.last_match(0) unless source_path

    dest_rel = File.join("assets", asset_name(report[:key], source_path.basename.to_s))
    dest_path = SITE.join(dest_rel)
    FileUtils.mkdir_p(dest_path.dirname)
    FileUtils.cp(source_path, dest_path)
    copied << dest_rel
    wrapped = quote.empty? ? "#{dest_rel}#{tail}" : "#{quote}#{dest_rel}#{tail}#{quote}"
    "url(#{wrapped})"
  end

  [rewritten, copied.uniq.sort]
end

def validate!(html, output)
  refs = []
  html.scan(/(?:src|href)=["']([^"']+)["']/i) { |m| refs << m[0] }
  html.scan(/url\(([^)]+)\)/i) { |m| refs << m[0].strip.gsub(/\A['"]|['"]\z/, "") }
  local_refs = refs.uniq.select { |ref| local_url?(ref) }
  escaped = local_refs.select { |ref| ref.start_with?("../", "/") }
  missing = local_refs.reject do |ref|
    clean, = split_url(ref)
    next true if clean == "index.html"
    SITE.join(clean).file?
  end

  errors = []
  errors << "#{output}: escaped local refs: #{escaped.join(', ')}" unless escaped.empty?
  errors << "#{output}: missing local refs: #{missing.join(', ')}" unless missing.empty?
  raise errors.join("\n") unless errors.empty?

  { refs: refs.length, local_refs: local_refs.length }
end

def home_page
  cards = REPORTS.map do |report|
    <<~HTML
      <a class="choice-card #{report[:key]}" href="#{report[:output]}">
        <span class="kicker">#{report[:kicker]}</span>
        <h2>#{report[:title]}</h2>
        <p>#{report[:description]}</p>
        <span class="enter">进入研究 →</span>
      </a>
    HTML
  end.join("\n")

  cards << <<~HTML
    <a class="choice-card fde" href="fde-search.html">
      <span class="kicker">FDE / Direction First</span>
      <h2>探寻之旅</h2>
      <p>先走一遍怎么找到下一个海力士，再看方向优先选出的九家。</p>
      <span class="enter">进入研究 →</span>
    </a>
  HTML

  <<~HTML
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{SERIES_TITLE}</title>
      <style>
        :root{color-scheme:light;--ink:#171a16;--muted:#60675e;--line:#d9ddd3;--paper:#f6f3ec;--paper2:#ece8de;--green:#244f38;--blue:#243f63;--gold:#a76627;--rust:#7a4a1f}
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans SC",sans-serif;color:var(--ink);background:radial-gradient(circle at 25% 15%,rgba(167,102,39,.14),transparent 34%),linear-gradient(135deg,var(--paper),var(--paper2));}
        main{min-height:100vh;display:flex;flex-direction:column;justify-content:center;width:min(1180px,calc(100% - 40px));margin:0 auto;padding:56px 0}
        .eyebrow{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:var(--gold);font-weight:800}
        h1{margin:14px 0 10px;font-size:clamp(38px,6vw,76px);line-height:1.02;letter-spacing:0;font-weight:900}
        .lead{max-width:760px;margin:0 0 34px;color:var(--muted);font-size:18px;line-height:1.8}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px}
        .choice-card{min-height:340px;display:flex;flex-direction:column;justify-content:flex-end;padding:30px;border:1px solid rgba(23,26,22,.14);border-radius:8px;text-decoration:none;color:inherit;background:rgba(255,255,255,.52);box-shadow:0 24px 70px rgba(30,35,26,.10);transition:transform .18s ease,box-shadow .18s ease,border-color .18s ease}
        .choice-card:hover{transform:translateY(-3px);box-shadow:0 30px 90px rgba(30,35,26,.16);border-color:rgba(23,26,22,.28)}
        .choice-card.ai{background:linear-gradient(145deg,rgba(255,255,255,.72),rgba(226,237,231,.74))}
        .choice-card.china{background:linear-gradient(145deg,rgba(255,255,255,.72),rgba(237,229,216,.78))}
        .choice-card.fde{background:linear-gradient(145deg,rgba(255,255,255,.72),rgba(244,234,214,.82))}
        .kicker{font-size:12px;letter-spacing:.12em;text-transform:uppercase;font-weight:850;color:var(--gold)}
        h2{margin:10px 0 12px;font-size:clamp(27px,3vw,42px);line-height:1.15;letter-spacing:0}
        p{margin:0;color:var(--muted);font-size:16px;line-height:1.75}
        .enter{margin-top:28px;font-weight:850;color:var(--green)}
        .china .enter{color:var(--blue)}
        .fde .enter{color:var(--rust)}
        @media(max-width:760px){main{justify-content:flex-start;padding:36px 0}.grid{grid-template-columns:1fr}.choice-card{min-height:260px;padding:24px}.lead{font-size:16px}}
      </style>
      <link rel="stylesheet" href="assets/research-series.css">
      <link rel="icon" href="assets/favicon.svg" type="image/svg+xml">
    </head>
    <body class="research-series-page">
      #{series_header(current: true)}
      <main>
        <div class="eyebrow">Research Map</div>
        <h1>#{SERIES_TITLE}</h1>
        <p class="lead">三条研究线并行阅读：供需结构、中国变量，以及从探寻之旅走到方向优先九家。</p>
        <section class="grid" aria-label="研究入口">
          #{cards}
        </section>
      </main>
    </body>
    </html>
  HTML
end

FileUtils.mkdir_p(ASSETS)
results = []
REPORTS.each do |report|
  source_html = File.read(report[:source], encoding: "UTF-8")
  site_html, copied = rewrite_local_refs(source_html, report)
  site_html = decorate_report(site_html)
  SITE.join(report[:output]).write(site_html, mode: "w", encoding: "UTF-8")
  validation = validate!(site_html, report[:output])
  results << {
    source: report[:source].relative_path_from(WORKSPACE).to_s,
    output: report[:output],
    bytes: site_html.bytesize,
    copied: copied,
    validation: validation
  }
end

SITE.join("index.html").write(home_page, mode: "w", encoding: "UTF-8")

puts JSON.pretty_generate(site: SITE.relative_path_from(WORKSPACE).to_s, reports: results)
