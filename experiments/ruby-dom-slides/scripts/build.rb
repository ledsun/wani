require "fileutils"
require "bundler/setup"
require "tmpdir"

Dir.chdir(File.expand_path("..", __dir__)) do
  runtime = "node_modules/@ruby/4.0-wasm-wasi/dist"
  abort "Run npm ci first" unless File.file?("#{runtime}/ruby+stdlib.wasm")
  FileUtils.mkdir_p("public")
  Dir.mktmpdir("ruby-dom-slides-") do |stage|
    FileUtils.cp_r("lib/.", stage)
    %w[kramdown rexml].each do |name|
      spec = Gem::Specification.find_by_name(name)
      destination = File.join(stage, "bundle", name)
      FileUtils.mkdir_p(destination)
      FileUtils.cp_r(File.join(spec.full_gem_path, "lib"), destination)
    end
    command = ["bundle", "exec", "rbwasm", "pack", "#{runtime}/ruby+stdlib.wasm",
               "--dir", "#{stage}::/app", "--output", "public/slides.wasm"]
    abort "Packaging failed" unless system(*command)
  end
  FileUtils.cp("#{runtime}/browser.umd.js", "public/browser.umd.js")
  puts "Built public/slides.wasm (#{File.size('public/slides.wasm')} bytes)"
end
