require_relative "test_helper"
require "open3"
require "net/http"
require "timeout"
require "rbconfig"

class HTTPTest < Minitest::Test
  def test_real_cli_serves_selected_file_and_rejects_escape_then_shuts_down
    directory = Dir.mktmpdir("wani-http-")
    file = File.join(directory, "other.md")
    File.write(file, "# Selected file")
    File.write(File.join(directory, "private.txt"), "private")
    File.symlink("/etc/passwd", File.join(directory, "escape.svg"))
    root = File.expand_path("../..", __dir__)
    stdin, stdout, stderr, wait = Open3.popen3(RbConfig.ruby, "-I#{root}/lib", "#{root}/exe/wani", "serve", file, "--port", "0", "--bind", "127.0.0.1")
    line = Timeout.timeout(10) { stdout.gets }
    assert_match(/Wani: http:\/\/127.0.0.1:\d+\//, line)
    uri = URI(line[/http:\/\/\S+/])
    http = Net::HTTP.new(uri.host, uri.port, nil)
    response = http.get("/talk/slides.md")
    assert_equal "200", response.code
    assert_equal "# Selected file", response.body
    assert_includes http.get("/").body, "data-ruby-wasm-url"
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
    assert_equal "application/wasm", http.head("/assets/wani.wasm")["Content-Type"]
    %w[Regular Bold].each do |weight|
      font = http.get("/assets/fonts/IBMPlexSansJP-#{weight}.woff2")
      assert_equal "200", font.code
      assert_equal "font/woff2", font["Content-Type"]
      assert_equal "wOF2", font.body.byteslice(0, 4)
    end
    assert_equal "404", http.get("/assets/fonts/unknown.woff2").code
    assert_equal "404", http.get("/talk/private.txt").code
    %w[/talk/%2e%2e/etc/passwd.svg /talk/%252e%252e/etc/passwd.svg /talk/escape.svg].each do |path|
      assert_equal "403", http.get(path).code, path
    end
    assert_equal "405", http.post("/", "").code
    Process.kill("INT", wait.pid)
    assert Timeout.timeout(10) { wait.value }.success?
  ensure
    if wait&.alive?
      Process.kill("TERM", wait.pid)
      wait.join(5)
    end
    [stdin, stdout, stderr].compact.each(&:close)
    FileUtils.remove_entry(directory) if directory
  end
end
