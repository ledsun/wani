require "bundler/setup"
require "bundler"
require "tmpdir"
require "open3"
require "net/http"
require "timeout"
require "rbconfig"
require "digest"
require "brotli"

root = File.expand_path("..", __dir__)
dependency_paths = Gem.path

def capture!(*command, **options)
  stdout, stderr, status = Open3.capture3(*command, **options)
  abort "#{command.join(' ')} failed:\n#{stdout}\n#{stderr}" unless status.success?
  puts stdout unless stdout.empty?
  stdout
end

Dir.mktmpdir("wani-installed-") do |directory|
  package = File.join(directory, "wani.gem")
  capture!("gem", "build", "wani.gemspec", "--output", package, chdir: root)
  Bundler.with_unbundled_env do
    home = File.join(directory, "gems")
    env = { "GEM_HOME" => home, "GEM_PATH" => ([home] + dependency_paths).join(File::PATH_SEPARATOR) }
    capture!(env, "gem", "install", "--local", "--ignore-dependencies", "--no-document", "--install-dir", home, package)
    executable = File.join(home, "bin", "wani")
    talk = File.join(directory, "talk")
    capture!(env, RbConfig.ruby, executable, "new", talk)
    capture!(env, RbConfig.ruby, executable, "check", chdir: talk)
    installed_root = capture!(env, RbConfig.ruby, "-rwani", "-e", "puts Wani::ROOT").strip
    abort "Source checkout was used instead of installed gem" unless installed_root.start_with?(home + File::SEPARATOR)
    abort "Uncompressed wasm was installed" if File.exist?(File.join(installed_root, "assets/wani.wasm"))
    abort "Gzip wasm was installed" if File.exist?(File.join(installed_root, "assets/wani.wasm.gz"))
    br = File.binread(File.join(installed_root, "assets/wani.wasm.br"))
    wasm = File.binread(File.join(root, "assets/wani.wasm"))
    abort "Installed wasm differs from build" unless Brotli.inflate(br) == wasm
    timer_images = (1..4).map { |number| "assets/time-expired-#{number}.webp" }
    timer_images.each do |timer_image|
      abort "Installed #{timer_image} differs from source" unless Digest::SHA256.file(File.join(installed_root, timer_image)).hexdigest == Digest::SHA256.file(File.join(root, timer_image)).hexdigest
    end
    %w[ZenKakuGothicNew UDEVGothic].product(%w[Regular Bold]).each do |family, weight|
      extension = "woff2"
      relative = "assets/fonts/#{family}-#{weight}.#{extension}"
      abort "Installed #{weight} font differs from source" unless Digest::SHA256.file(File.join(installed_root, relative)).hexdigest == Digest::SHA256.file(File.join(root, relative)).hexdigest
    end
    abort "Font license missing from gem" unless File.file?(File.join(installed_root, "assets/fonts/ZenKakuGothicNew-OFL.txt"))
    abort "UDEV Gothic license missing from gem" unless File.file?(File.join(installed_root, "third_party/udev-gothic/LICENSE.txt"))
    stdin, stdout, stderr, wait = Open3.popen3(env, RbConfig.ruby, executable, "serve", "--port", "0", chdir: talk)
    begin
      line = Timeout.timeout(10) { stdout.gets }
      uri = URI(line[/http:\/\/\S+/])
      http = Net::HTTP.new(uri.host, uri.port, nil)
      abort "Installed server did not serve HTML" unless http.get("/").code == "200"
      timer_images.each do |timer_image|
        abort "Installed server did not serve #{timer_image}" unless http.get("/#{timer_image}").code == "200"
      end
      abort "Installed server did not serve Markdown" unless http.get("/talk/slides.md").code == "200"
      wasm_path = "/assets/wani.wasm"
      compressed = http.get(wasm_path, "Accept-Encoding" => "br")
      abort "Installed Brotli wasm unavailable" unless compressed.code == "200" &&
        compressed["Content-Type"] == "application/wasm" && compressed["Content-Encoding"] == "br" &&
        compressed["Vary"] == "Accept-Encoding" && compressed.body == br
      identity = http.get(wasm_path, "Accept-Encoding" => "identity")
      abort "Installed identity wasm unavailable" unless identity.code == "200" &&
        identity["Content-Encoding"].nil? && identity.body == wasm
      abort "Installed font unavailable" unless http.head("/assets/fonts/ZenKakuGothicNew-Regular.woff2")["Content-Type"] == "font/woff2"
      abort "Installed UDEV Gothic font unavailable" unless http.head("/assets/fonts/UDEVGothic-Regular.woff2")["Content-Type"] == "font/woff2"
      Process.kill("INT", wait.pid)
      abort "Installed server failed to stop" unless Timeout.timeout(10) { wait.value }.success?
      puts "Installed gem: new / check / serve / browser assets / SIGINT all passed"
    ensure
      if wait.alive?
        Process.kill("TERM", wait.pid)
        wait.join(5)
      end
      [stdin, stdout, stderr].each(&:close)
    end
  end
end
