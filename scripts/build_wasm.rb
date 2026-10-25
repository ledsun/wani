require "bundler/setup"
require "fileutils"
require "tmpdir"
require "json"
require "digest"

root = File.expand_path("..", __dir__)
Dir.chdir(root) do
  runtime = "node_modules/@ruby/4.0-wasm-wasi/dist"
  abort "Run npm ci before building wasm" unless File.file?("#{runtime}/ruby+stdlib.wasm")
  loader_root = "third_party/ruby-wasm-loader"
  provenance = JSON.parse(File.read("#{loader_root}/provenance.json"))
  loader = "#{loader_root}/browser.script.iife.js"
  abort "PR loader checksum mismatch" unless Digest::SHA256.file(loader).hexdigest == provenance.fetch("loader_sha256")
  source_digest = Digest::SHA256.new
  Dir["lib/wani/{core,browser}/**/*.rb"].sort.each { |file| source_digest << file << File.binread(file) }
  Dir.mktmpdir("wani-pack-") do |stage|
    FileUtils.mkdir_p("#{stage}/lib/wani")
    %w[core browser].each { |name| FileUtils.cp_r("lib/wani/#{name}", "#{stage}/lib/wani/") }
    %w[kramdown rexml kramdown-parser-gfm].each do |name|
      spec = Gem::Specification.find_by_name(name)
      destination = File.join(stage, "bundle", name)
      FileUtils.mkdir_p(destination)
      FileUtils.cp_r(File.join(spec.full_gem_path, "lib"), destination)
    end
    command = ["bundle", "exec", "rbwasm", "pack", "#{runtime}/ruby+stdlib.wasm", "--dir", "#{stage}::/wani", "--output", "assets/wani.wasm"]
    abort "Packaging failed" unless system(*command)
  end
  FileUtils.cp(loader, "assets/runtime.pr672.js")
  %w[LICENSE NOTICE].each { |name| FileUtils.cp("#{loader_root}/#{name}", "assets/runtime.#{name}") }
  File.write("assets/build.json", JSON.pretty_generate({ version: "0.1.0", source_sha256: source_digest.hexdigest, loader_commit: provenance.fetch("commit"), wasm_sha256: Digest::SHA256.file("assets/wani.wasm").hexdigest }))
  puts "Built assets/wani.wasm (#{File.size('assets/wani.wasm')} bytes)"
end
