require "bundler/setup"
require "bundler"
require "tmpdir"
require "open3"
require "net/http"
require "timeout"
require "rbconfig"
require "digest"

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
    abort "Installed wasm differs from build" unless Digest::SHA256.file(File.join(installed_root, "assets/wani.wasm")).hexdigest == Digest::SHA256.file(File.join(root, "assets/wani.wasm")).hexdigest
    timer_image = "assets/time-expired.webp"
    abort "Installed timer image differs from source" unless Digest::SHA256.file(File.join(installed_root, timer_image)).hexdigest == Digest::SHA256.file(File.join(root, timer_image)).hexdigest
    %w[Regular Bold].each do |weight|
      relative = "assets/fonts/IBMPlexSansJP-#{weight}.woff2"
      abort "Installed #{weight} font differs from source" unless Digest::SHA256.file(File.join(installed_root, relative)).hexdigest == Digest::SHA256.file(File.join(root, relative)).hexdigest
    end
    abort "Font license missing from gem" unless File.file?(File.join(installed_root, "third_party/ibm-plex-sans-jp/LICENSE.txt"))
    stdin, stdout, stderr, wait = Open3.popen3(env, RbConfig.ruby, executable, "serve", "--port", "0", chdir: talk)
    begin
      line = Timeout.timeout(10) { stdout.gets }
      uri = URI(line[/http:\/\/\S+/])
      http = Net::HTTP.new(uri.host, uri.port, nil)
      abort "Installed server did not serve HTML" unless http.get("/").code == "200"
      abort "Installed server did not serve timer image" unless http.get("/assets/time-expired.webp").code == "200"
      abort "Installed server did not serve Markdown" unless http.get("/talk/slides.md").code == "200"
      abort "Installed wasm unavailable" unless http.head("/assets/wani.wasm")["Content-Type"] == "application/wasm"
      abort "Installed font unavailable" unless http.head("/assets/fonts/IBMPlexSansJP-Regular.woff2")["Content-Type"] == "font/woff2"
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
