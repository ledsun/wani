require "fileutils"
require "bundler/setup"
require "tmpdir"
require "json"
require "digest"

Dir.chdir(File.expand_path("..", __dir__)) do
  runtime = "node_modules/@ruby/4.0-wasm-wasi/dist"
  abort "Run npm ci first" unless File.file?("#{runtime}/ruby+stdlib.wasm")
  loader_root = "third_party/ruby-wasm-loader"
  provenance = JSON.parse(File.read("#{loader_root}/provenance.json"))
  loader = "#{loader_root}/browser.script.iife.js"
  abort "Vendored PR loader checksum mismatch" unless Digest::SHA256.file(loader).hexdigest == provenance.fetch("loader_sha256")
  FileUtils.mkdir_p("public")
  Dir.mktmpdir("mvp-preflight-") do |stage|
    FileUtils.cp_r("lib/.", stage)
    %w[kramdown rexml kramdown-parser-gfm].each do |name|
      spec = Gem::Specification.find_by_name(name)
      destination = File.join(stage, "bundle", name)
      FileUtils.mkdir_p(destination)
      FileUtils.cp_r(File.join(spec.full_gem_path, "lib"), destination)
    end
    command = ["bundle", "exec", "rbwasm", "pack", "#{runtime}/ruby+stdlib.wasm",
               "--dir", "#{stage}::/app", "--output", "public/preflight.wasm"]
    abort "Packaging failed" unless system(*command)
  end
  FileUtils.cp(loader, "public/runtime.pr672.js")
  %w[LICENSE NOTICE].each { |name| FileUtils.cp("#{loader_root}/#{name}", "public/runtime.#{name}") }
  FileUtils.cp("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "public/test-font.ttf")
  puts "Built public/preflight.wasm (#{File.size('public/preflight.wasm')} bytes)"
end
