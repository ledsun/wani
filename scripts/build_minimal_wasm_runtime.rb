require "open3"
require "rubygems/package"
require "rubygems/remote_fetcher"
require "ruby_wasm"
require "ruby_wasm/cli"

def build_minimal_wasm_runtime(probe, stage)
  extensions, status = Open3.capture2("node", "scripts/detect_wasm_extensions.mjs", "--wasm", probe)
  extensions = extensions.strip
  abort "WASM extension detection failed" unless status.success? && extensions.match?(/\A[\w\/]+(?:,[\w\/]+)*\z/)
  puts "Building Ruby WASM with extensions #{extensions}"

  js_name = "js-2.10.1"
  js_checksum = "c5fb88c60ea936234f818ff240f2ab0c42a57c25ab9b575211fcc4d702d059fb"
  cli = RubyWasm::CLI.new(stdout: $stdout, stderr: $stderr)
  config = cli.send(:build_config, ruby_version: "4.0", target_triplet: "wasm32-unknown-wasip1", profile: "minimal", patches: [])
  config[:default_exts] = extensions
  # rbwasm's build directory name does not otherwise include the extension list.
  config[:suffix] += "-#{Digest::SHA256.hexdigest(extensions)[0, 16]}"
  workspace = File.expand_path("vendor/wani-wasm/#{RubyWasm::VERSION}")
  FileUtils.mkdir_p(workspace)

  File.open(File.join(workspace, "build.lock"), "w") do |lock|
    lock.flock(File::LOCK_EX)
    archive = File.join(workspace, "#{js_name}.gem")
    unless File.file?(archive)
      bytes = Gem::RemoteFetcher.fetcher.fetch_path("https://rubygems.org/downloads/#{js_name}.gem")
      abort "JS gem checksum mismatch" unless Digest::SHA256.hexdigest(bytes) == js_checksum
      File.binwrite(archive, bytes)
    end
    abort "JS gem checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == js_checksum
    package = Gem::Package.new(archive)
    js = package.spec
    js.full_gem_path = File.join(workspace, js_name)
    package.extract_files(js.full_gem_path)

    packager = RubyWasm::Packager.new(workspace, config)
    packager.define_singleton_method(:specs) { [js] }
    executor = RubyWasm::BuildExecutor.new
    tarball = packager.ruby_core_build.build(executor, {})
    runtime_file = File.join(File.basename(tarball, ".tar.gz"), "usr/local/bin/ruby")
    executor.system("tar", "-xzf", tarball, "-C", stage, runtime_file)
    output = File.join(stage, "ruby.wasm")
    executor.system(packager.full_build_options.fetch(:toolchain).wasm_opt, "--strip-debug", File.join(stage, runtime_file), "-o", output)
    output
  end
end
