require "fileutils"
require "bundler/setup"
require "tmpdir"

Dir.chdir(File.expand_path("..", __dir__)) do
  runtime = "node_modules/@ruby/4.0-wasm-wasi/dist"
  abort "Run npm ci first" unless File.file?("#{runtime}/ruby+stdlib.wasm")
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
  loader = File.binread("#{runtime}/browser.script.iife.js")
  original = '`https://cdn.jsdelivr.net/npm/${pkg.name}@${pkg.version}/dist/ruby+stdlib.wasm`'
  abort "Upstream loader changed; inspect before configuring" unless loader.scan(original).length == 1
  File.binwrite("public/runtime.local.js", loader.sub(original, '"./preflight.wasm"'))
  FileUtils.cp("#{runtime}/browser.script.iife.js", "public/runtime.original.js")
  %w[LICENSE NOTICE].each { |name| FileUtils.cp("#{runtime}/#{name}", "public/runtime.#{name}") }
  FileUtils.cp("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "public/test-font.ttf")
  puts "Built public/preflight.wasm (#{File.size('public/preflight.wasm')} bytes)"
end
