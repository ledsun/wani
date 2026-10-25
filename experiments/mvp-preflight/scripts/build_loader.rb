require "json"
require "digest"
require "fileutils"
require "tmpdir"

root = File.expand_path("..", __dir__)
destination = File.join(root, "third_party/ruby-wasm-loader")
provenance = JSON.parse(File.read(File.join(destination, "provenance.json")))
commit = provenance.fetch("commit")
abort "Invalid pinned commit" unless commit.match?(/\A[0-9a-f]{40}\z/)

def run!(*command, **options)
  abort "Failed: #{command.join(' ')}" unless system(*command, **options)
end

Dir.mktmpdir("wani-pr672-") do |temporary|
  archive = File.join(temporary, "source.tar.gz")
  url = "#{provenance.fetch('repository').sub('https://github.com/', 'https://codeload.github.com/')}/tar.gz/#{commit}"
  run!("curl", "--fail", "--location", "--retry", "2", "--output", archive, url)
  abort "Source archive checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == provenance.fetch("archive_sha256")
  run!("tar", "-xzf", archive, "-C", temporary)
  source = File.join(temporary, "ruby.wasm-#{commit}")
  run!("npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund",
       "--workspace=@ruby/wasm-wasi", "--workspace=@ruby/4.0-wasm-wasi", "--include-workspace-root", chdir: source)
  run!("npm", "run", "build:tsc", "--workspace=@ruby/wasm-wasi", chdir: source)
  run!("npm", "run", "build:rollup", "--workspace=@ruby/4.0-wasm-wasi", chdir: source)
  loader = File.join(source, "packages/npm-packages/ruby-4.0-wasm-wasi/dist/browser.script.iife.js")
  abort "Loader checksum mismatch; inspect build before updating the pin" unless Digest::SHA256.file(loader).hexdigest == provenance.fetch("loader_sha256")
  FileUtils.cp(loader, File.join(destination, "browser.script.iife.js"))
  %w[LICENSE NOTICE].each { |name| FileUtils.cp(File.join(source, name), File.join(destination, name)) }
  puts "Rebuilt PR #672 loader at #{commit} (SHA-256 verified)"
end
