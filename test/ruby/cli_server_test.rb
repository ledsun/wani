require_relative "test_helper"
require "wani/cli"
require "wani/server/application"

class CLIServerTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("wani-test-")
    @out, @err = StringIO.new, StringIO.new
    @cli = Wani::CLI.new(out: @out, err: @err)
    @talk = File.join(@directory, "talk")
    assert_equal 0, @cli.run(["new", @talk])
    @assets = File.join(@directory, "assets")
    Dir.mkdir(@assets)
    File.write(File.join(@assets, "index.html"), "app")
    @application = Wani::Server::Application.new(File.join(@talk, "slides.md"), assets: @assets)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_new_has_only_document_and_images_and_refuses_existing_target
    assert_equal %w[images slides.md], Dir.children(@talk).sort
    original = File.read(File.join(@talk, "slides.md"))
    assert_includes original, "<!-- notes:"
    assert_equal 1, @cli.run(["new", @talk])
    assert_equal original, File.read(File.join(@talk, "slides.md"))
  end

  def test_generated_sample_has_valid_slides_and_a_served_image
    assert_equal 0, @cli.run(["check", File.join(@talk, "slides.md")])
    assert_includes @out.string, "10 slides; 0 diagnostics"
    status, headers, body = @application.call("/talk/images/workflow.svg")
    assert_equal 200, status
    assert_includes headers["Content-Type"], "image/svg+xml"
    assert_includes body, "<svg"
    spec = Gem::Specification.load(File.join(Wani::ROOT, "wani.gemspec"))
    assert_includes spec.files, "templates/images/workflow.svg"
  end

  def test_routes_app_document_and_images_but_not_private_files
    assert_equal [200, "app"], @application.call("/").values_at(0, 2)
    assert_equal 200, @application.call("/talk/slides.md")[0]
    File.write(File.join(@talk, "images", "space name.svg"), "<svg/>")
    assert_equal 200, @application.call("/talk/images/space%20name.svg")[0]
    File.write(File.join(@talk, "secret.txt"), "private")
    assert_equal 404, @application.call("/talk/secret.txt")[0]
    assert_equal 404, @application.call("/assets/secret.txt")[0]
    assert_equal 404, @application.call("/talk/missing.svg")[0]
  end

  def test_traversal_and_encoding_are_denied
    %w[/talk/../secret.svg /talk/%2e%2e/secret.svg /talk/%252e%252e/secret.svg /talk/%2e%2e%2fsecret.svg /talk/%5csecret.svg /talk/%00.svg /talk/%ff.svg /talk/%xx.svg /assets/../secret.svg].each do |path|
      assert_equal 403, @application.call(path)[0], path
    end
  end

  def test_symlink_escape_is_denied
    outside = File.join(@directory, "secret.svg")
    File.write(outside, "secret")
    File.symlink(outside, File.join(@talk, "images", "escape.svg"))
    assert_equal 403, @application.call("/talk/images/escape.svg")[0]
    File.symlink(@directory, File.join(@talk, "images", "outside"))
    assert_equal 403, @application.call("/talk/images/outside/secret.svg")[0]
  end
end
