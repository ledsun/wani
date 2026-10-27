require_relative "test_helper"
require "wani/fonts/manager"
require "wani/cli"
require "wani/server/application"

class FontsTest < Minitest::Test
  class Responses
    attr_reader :urls
    attr_accessor :fail, :variable, :weights, :corrupt, :catalog
    def initialize
      @urls, @variable, @weights = [], true, [400, 700]
    end

    def get(url)
      @urls << url
      raise Wani::Fonts::Error, "mock download failed" if fail && url.include?(fail)
      id = 'noto-sans-jp'
      meta = { id: id, family: 'Noto Sans JP', variable: variable, weights: weights, styles: ['normal'], subsets: ['japanese', 'latin'] }
      case url
      when %r{/v1/fonts$} then JSON.generate(catalog || [meta])
      when %r{/v1/fonts/} then JSON.generate(meta)
      when %r{/v1/version/} then JSON.generate(latest: '5.3.1', latestVariable: '5.3.1')
      when /package.json$/ then JSON.generate(name: "@fontsource#{variable ? '-variable' : ''}/#{id}", version: '5.3.1', license: 'OFL-1.1')
      when /\.css$/
        %w[0 1 latin].map do |subset|
          "@font-face { font-family: 'Noto Sans JP#{variable ? ' Variable' : ''}'; font-weight: #{variable ? '100 900' : url[/\/(\d+)\.css/, 1]}; font-style: normal; src: url(./files/#{subset}.woff2) format('woff2'), url(./files/#{subset}.woff) format('woff'); unicode-range: #{subset == 'latin' ? 'U+0000-00FF' : "U+4E0#{subset}"}; }"
        end.join("\n")
      when /\.woff2$/ then corrupt ? 'wOF2broken' : 'wOF2' + "\x00" * 4 + [48].pack('N') + "\x00" * 36
      when /LICENSE$/ then "Copyright test fixture\nSIL OPEN FONT LICENSE Version 1.1\n" + 'License text. ' * 20
      else raise "Unexpected request: #{url}"
      end
    end
  end

  def setup
    @root = Dir.mktmpdir('wani-font-test-')
    @http = Responses.new
    @manager = Wani::Fonts::Manager.new(@root, http: @http)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_add_name_preserves_every_subset_and_pins_package
    entry = @manager.add('Noto Sans JP')
    assert_equal '5.3.1', entry['version']
    assert_equal true, entry['variable']
    assert_equal 'OFL-1.1', entry['license_type']
    assert_equal 'Noto Sans JP Variable', entry['css_family']
    assert_equal 3, Dir["#{@root}/fonts/**/*.woff2"].size
    css = File.read(File.join(@root, entry['stylesheet']))
    assert_includes css, 'U+4E00'
    assert_includes css, 'U+4E01'
    assert_includes css, "url('./files/latin.woff2')"
    refute_includes css, '.woff)'
    refute @http.urls.any? { |url| url.include?('@latest') }
    assert File.read(File.join(@root, entry['license'])).include?('SIL OPEN FONT LICENSE')
    assert_equal entry, @manager.list['noto-sans-jp']
  end

  def test_url_and_duplicate
    @manager.add('https://fontsource.org/fonts/noto-sans-jp')
    assert_raises(Wani::Fonts::Error) { @manager.add('Noto Sans JP') }
  end

  def test_remove_preserves_user_files_and_blocks_used_fonts
    @manager.add('Noto Sans JP')
    File.write("#{@root}/slides.md", "---\nfont: Noto Sans JP\n---\n# Hello")
    assert_raises(Wani::Fonts::Error) { @manager.remove('noto-sans-jp') }
    File.write("#{@root}/fonts/noto-sans-jp/user.txt", 'keep')
    @manager.remove('noto-sans-jp', confirm: ->(_) { true })
    assert_empty @manager.list
    assert_equal 'keep', File.read("#{@root}/fonts/noto-sans-jp/user.txt")
    refute File.exist?("#{@root}/fonts/noto-sans-jp/font.css")
  end

  def test_modified_files_and_symlinks_are_not_deleted
    @manager.add('Noto Sans JP')
    File.write("#{@root}/fonts/noto-sans-jp/font.css", 'user changes')
    assert_raises(Wani::Fonts::Error) { @manager.remove('noto-sans-jp') }
    File.symlink('/tmp', "#{@root}/fonts/other")
    assert_raises(Wani::Fonts::Error) { @manager.send(:safe_path, 'fonts/other/secret') }
  end

  def test_failures_leave_no_registration_or_font_files
    ['v1/fonts', '.css', '.woff2', 'LICENSE'].each do |failure|
      @http.fail = failure
      assert_raises(Wani::Fonts::Error) { @manager.add('Noto Sans JP') }
      assert_empty @manager.list
      refute File.exist?("#{@root}/fonts/noto-sans-jp")
      assert_empty Dir["#{@root}/.wani-font-*"]
    end
    @http.fail = nil
    @http.corrupt = true
    assert_raises(Wani::Fonts::Error) { @manager.add('Noto Sans JP') }
    assert_empty @manager.list
  end

  def test_invalid_urls_are_rejected_before_network
    ['http://fontsource.org/fonts/noto-sans-jp', 'https://evil.test/fonts/noto-sans-jp', 'https://fontsource.org/fonts/../secret', 'https://fontsource.org/fonts/noto-sans-jp?x=1', '/tmp/font.woff2'].each do |source|
      assert_raises(Wani::Fonts::Error) { @manager.add(source) }
    end
    assert_empty @http.urls
    assert_raises(Wani::Fonts::Error) { Wani::Fonts::HTTP.new.get('https://evil.test/a') }
  end

  def test_static_weights_and_unavailable_weights
    @http.variable = false
    @manager.add('Noto Sans JP')
    assert @http.urls.any? { |url| url.end_with?('/400.css') }
    assert @http.urls.any? { |url| url.end_with?('/700.css') }
    @manager.remove('noto-sans-jp')
    @http.weights = [300]
    assert_raises(Wani::Fonts::Error) { @manager.add('Noto Sans JP') }
  end

  def test_cli_list_remove_and_validation
    @manager.add('Noto Sans JP')
    out, err = StringIO.new, StringIO.new
    cli = Wani::CLI.new(out: out, err: err)
    Dir.chdir(@root) do
      assert_equal 0, cli.run(['font', 'list'])
      assert_includes out.string, "noto-sans-jp\tNoto Sans JP\t5.3.1\ttrue"
      assert_equal 0, cli.run(['font', 'remove', 'noto-sans-jp'])
      assert_equal 1, cli.run(['font', 'add', 'https://evil.test/fonts/a'])
    end
  end

  def test_cli_add_name_url_duplicate_and_http_error
    cli = Wani::CLI.new(out: StringIO.new, err: StringIO.new, font_manager: @manager)
    assert_equal 0, cli.run(['font', 'add', 'Noto Sans JP'])
    assert_equal 1, cli.run(['font', 'add', 'noto-sans-jp'])
    assert_equal 0, cli.run(['font', 'remove', 'noto-sans-jp'])
    assert_equal 0, cli.run(['font', 'add', 'https://fontsource.org/fonts/noto-sans-jp'])
    @manager.remove('noto-sans-jp')
    @http.fail = 'v1/fonts'
    assert_equal 1, cli.run(['font', 'add', 'Noto Sans JP'])
  end

  def test_cli_add_reports_start_before_downloading_when_redirected
    out, err = StringIO.new, StringIO.new
    manager = Object.new
    manager.define_singleton_method(:add) do |_source|
      assert_message = err.string
      raise "Missing start message" unless assert_message == "Downloading font...\n"
      { 'family' => 'Test Font', 'version' => '1.0.0' }
    end
    cli = Wani::CLI.new(out: out, err: err, font_manager: manager)
    assert_equal 0, cli.run(['font', 'add', 'test-font'])
    assert_equal "Downloading font...\n", err.string
    assert_includes out.string, 'Installed Test Font (1.0.0)'
  end

  def test_cli_add_animates_and_stops_on_success_failure_and_interrupt
    [nil, Wani::Fonts::Error.new('download failed'), Interrupt.new].each do |failure|
      out, err = StringIO.new, StringIO.new
      frames = Queue.new
      err.define_singleton_method(:tty?) { true }
      err.define_singleton_method(:print) do |text|
        super(text)
        frames << Thread.current if text == "\rDownloading font.. "
      end
      animation = nil
      manager = Object.new
      manager.define_singleton_method(:add) do |_source|
        animation = Timeout.timeout(5) { frames.pop }
        raise failure if failure
        { 'family' => 'Test Font', 'version' => '1.0.0' }
      end
      cli = Wani::CLI.new(out: out, err: err, font_manager: manager)
      if failure.is_a?(Interrupt)
        assert_raises(Interrupt) { cli.run(['font', 'add', 'test-font']) }
      else
        assert_equal(failure ? 1 : 0, cli.run(['font', 'add', 'test-font']))
      end
      refute animation.alive?
      assert_includes err.string, "\r#{' ' * 19}\r"
      if failure
        refute_includes out.string, 'Installed'
        assert_includes err.string, 'wani: download failed' unless failure.is_a?(Interrupt)
      else
        assert_includes out.string, 'Installed Test Font'
      end
    end
  end

  def test_ambiguous_and_missing_fonts
    @http.catalog = [{ id: 'noto-sans-jp', family: 'Noto Sans JP' }, { id: 'noto-sans', family: 'Noto Sans' }]
    error = assert_raises(Wani::Fonts::Error) { @manager.add('Noto') }
    assert_includes error.message, 'noto-sans-jp, noto-sans'
    assert_raises(Wani::Fonts::Error) { @manager.add('Missing') }
  end

  def test_registry_commit_failure_rolls_back_add_and_remove
    @manager.define_singleton_method(:save) { |_| raise IOError, 'disk failure' }
    assert_raises(IOError) { @manager.add('Noto Sans JP') }
    refute File.exist?("#{@root}/fonts/noto-sans-jp")
    assert_empty @manager.list
    @manager.singleton_class.remove_method(:save)
    @manager.add('Noto Sans JP')
    @manager.define_singleton_method(:save) { |_| raise IOError, 'disk failure' }
    assert_raises(IOError) { @manager.remove('noto-sans-jp') }
    assert File.file?("#{@root}/fonts/noto-sans-jp/font.css")
    assert @manager.list.key?('noto-sans-jp')
  end

  def test_core_and_server
    assert_equal({ 'default' => 'Noto Sans JP' }, Wani::Core::Parser.new.parse("---\nfont: Noto Sans JP\n---\n# Text").fonts)
    assert_raises(Wani::Core::Parser::Error) { Wani::Core::Parser.new.parse("---\nfont: []\n---\n# Text") }
    @manager.add('Noto Sans JP')
    File.write("#{@root}/slides.md", '# Text')
    File.write("#{@root}/fonts/noto-sans-jp/private.woff2", 'private')
    app = Wani::Server::Application.new("#{@root}/slides.md")
    assert_equal 200, app.call('/talk/fonts.json')[0]
    assert_equal 'font/woff2', app.call('/talk/fonts/noto-sans-jp/files/0.woff2')[1]['Content-Type']
    assert_equal 404, app.call('/talk/fonts/noto-sans-jp/private.woff2')[0]
    assert_equal 404, app.call('/talk/.wani/fonts.yml')[0]
  end
end
