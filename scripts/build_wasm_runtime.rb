require "open3"
require "digest"
require "fileutils"
require "rubygems/package"
require "rubygems/remote_fetcher"
require "ruby_wasm"
require "ruby_wasm/cli"
require "tmpdir"

WANI_WASM_RUBY_VERSION = "4.0.10"
WANI_WASM_RUBY_SHA256 = "b53eef3371fa5d3e3b74340edcd015f06d5d8853968d4e539a5264fce41ed9f1"

WANI_WASM_PRISM_ONLY_PATCH = File.join(__dir__, "patches/ruby-#{WANI_WASM_RUBY_VERSION}-prism-only.patch")

def detect_wasm_extensions(probe)
  extensions, status = Open3.capture2("node", "scripts/detect_wasm_extensions.mjs", "--wasm", probe)
  extensions = extensions.strip
  abort "WASM extension detection failed" unless status.success? && extensions.match?(/\A[\w\/]+(?:,[\w\/]+)*\z/)
  extensions
end

def prepare_wasm_ruby_source(workspace, url)
  checkouts = File.join(workspace, "build/checkouts")
  source = File.join(checkouts, WANI_WASM_RUBY_VERSION)
  return source if File.file?(File.join(source, "configure"))

  FileUtils.mkdir_p(checkouts)
  Dir.mktmpdir("ruby-source-", checkouts) do |directory|
    archive = File.join(directory, "ruby.tar.gz")
    abort "Ruby download failed" unless system("curl", "--fail", "-L", "-o", archive, url)
    abort "Ruby source checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == WANI_WASM_RUBY_SHA256

    extracted = File.join(directory, "source")
    Dir.mkdir(extracted)
    abort "Ruby extraction failed" unless system("tar", "-xzf", archive, "-C", extracted, "--strip-components=1")
    File.rename(extracted, source)
  end
  source
end

def prepare_prism_only_source(source, patch_digest)
  destination = "#{source}-prism-only-#{patch_digest}"
  return destination if File.file?(File.join(destination, "configure"))

  Dir.mktmpdir("ruby-prism-only-", File.dirname(source)) do |directory|
    extracted = File.join(directory, "source")
    FileUtils.cp_r(source, extracted, preserve: true)
    abort "Prism-only patch failed" unless system("patch", "--batch", "--fuzz=0", "-p1",
      "-d", extracted, "-i", WANI_WASM_PRISM_ONLY_PATCH)
    File.rename(extracted, destination)
  end
  destination
end

def build_wasm_runtime(stage, extensions: nil)
  minimal = !extensions.nil?
  profile = minimal ? "minimal" : "full"
  puts "Building Ruby #{WANI_WASM_RUBY_VERSION} WASM (#{profile})"
  puts "Using extensions #{extensions}" if minimal

  js_name = "js-2.10.1"
  js_checksum = "c5fb88c60ea936234f818ff240f2ab0c42a57c25ab9b575211fcc4d702d059fb"
  cli = RubyWasm::CLI.new(stdout: $stdout, stderr: $stderr)
  config = cli.send(:build_config, ruby_version: "4.0", target_triplet: "wasm32-unknown-wasip1", profile: profile, patches: [])
  url = "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-#{WANI_WASM_RUBY_VERSION}.tar.gz"
  config[:src] = config.fetch(:src).merge(name: WANI_WASM_RUBY_VERSION, url: url)
  encoding_options = "--encs=utf_16* --transes=utf_16_32"
  optimization = "-Oz"
  if minimal
    patch_digest = Digest::SHA256.file(WANI_WASM_PRISM_ONLY_PATCH).hexdigest[0, 16]
    config[:default_exts] = extensions
    # rbwasm's build directory name omits these build settings.
    config[:suffix] += "-#{Digest::SHA256.hexdigest([extensions, encoding_options, optimization, patch_digest].join("\n"))[0, 16]}"
  end
  workspace = File.expand_path("vendor/wani-wasm/#{RubyWasm::VERSION}")
  FileUtils.mkdir_p(workspace)

  File.open(File.join(workspace, "build.lock"), "w") do |lock|
    lock.flock(File::LOCK_EX)
    source = prepare_wasm_ruby_source(workspace, url)
    # Use the unmodified host Ruby and patch only the lightweight WASI build.
    prism_only_source = prepare_prism_only_source(source, patch_digest) if minimal
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
    # CRuby's makefiles forward ENCS to the static encoding generator.
    executor.define_singleton_method(:system) do |*args, chdir: nil, env: nil|
      env = (env || {}).merge("ENCS" => encoding_options) if minimal && args.first == "make"
      if minimal && File.basename(args.first) == "configure" && args.include?("wasm32-wasi")
        args[0] = File.join(prism_only_source, "configure")
        args << "optflags=#{optimization} -fno-fast-math"
      end
      super(*args, chdir: chdir, env: env)
    end
    tarball = packager.ruby_core_build.build(executor, {})
    runtime_root = File.basename(tarball, ".tar.gz")
    runtime_file = "#{runtime_root}/usr/local/bin/ruby"
    stdlib = "#{runtime_root}/usr/local/lib/ruby/4.0.0"
    entries = minimal ? [runtime_file] : [runtime_file, stdlib]
    executor.system("tar", "-xzf", tarball, "-C", stage, *entries)
    output = File.join(stage, "#{profile}.wasm")
    executor.system(packager.full_build_options.fetch(:toolchain).wasm_opt, "--strip-debug", File.join(stage, runtime_file), "-o", output)
    prepare_wasm_runtime(File.join(stage, stdlib), js.full_gem_path, stage) unless minimal
    output
  end
end

def prepare_wasm_runtime(stdlib, js_gem, stage)
  lib = File.join(stage, "runtime/usr/local/lib/ruby/4.0.0")
  FileUtils.mkdir_p(lib)
  # Keep complete components, including dependencies that are loaded while rendering.
  components = %w[date json pathname psych strscan uri yaml cgi delegate forwardable set singleton time unicode_normalize]
  components.each do |name|
    [name, "#{name}.rb"].each do |entry|
      source = File.join(stdlib, entry)
      FileUtils.cp_r(source, lib) if File.exist?(source)
    end
  end

  bundle = File.join(stage, "runtime/bundle")
  js_target = File.join(bundle, "gems", File.basename(js_gem))
  FileUtils.mkdir_p(js_target)
  FileUtils.cp_r(File.join(js_gem, "lib"), js_target)
  File.write(File.join(bundle, "setup.rb"), "$LOAD_PATH.unshift('/bundle/gems/#{File.basename(js_gem)}/lib')\n")
end
