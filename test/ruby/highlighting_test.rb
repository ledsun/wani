require_relative "test_helper"
require "wani/core/parser"
require "rexml/document"
require "open3"

class HighlightingTest < Minitest::Test
  def slide(source)
    Wani::Core::Parser.new.parse(source).slides.first
  end

  def block(source, language = '')
    slide("```#{language}\n#{source}\n```\n").html
  end

  def test_known_languages_and_aliases
    { 'ruby' => 'puts "hello"', 'rb' => 'puts "hello"', 'javascript' => 'const x = 1;',
      'js' => 'const x = 1;', 'ts' => 'const x: number = 1;', 'python' => 'print("hello")',
      'sh' => 'echo "$HOME"', 'json' => '{"x": 1}', 'yaml' => 'x: 1',
      'html' => '<b>hello</b>', 'css' => 'body { color: red; }', 'sql' => 'SELECT 1;' }.each do |language, source|
      html = block(source, language)
      assert_includes html, '<pre class="highlight">', language
      assert_includes html, '<span class=', language
      document = REXML::Document.new(html)
      assert_equal "#{source}\n", REXML::XPath.match(document, '//text()').map(&:value).join, language
    end
  end

  def test_plain_unknown_and_empty_blocks_and_inline_code
    source = '<script>& "日本語"</script>'
    expected = "<pre><code>#{Wani::Core::SafeHTML.escape(source)}\n</code></pre>"
    assert_equal expected, block(source)
    assert_equal expected, block(source, 'wani-unknown')
    assert_equal '<p><code>&lt;b&gt;</code></p>', slide('`<b>`').html
    assert_equal '<pre class="highlight"><code></code></pre>', slide("```ruby\n```\n").html
  end

  def test_html_is_escaped_and_only_formatter_spans_are_emitted
    source = '<script>alert(1)</script><img src=x onerror=alert(2)> & 日本語'
    %w[html ruby text].each do |language|
      html = block(source, language)
      document = REXML::Document.new(html)
      assert_equal "#{source}\n", REXML::XPath.match(document, '//text()').map(&:value).join
      REXML::XPath.each(document, '//*') do |element|
        assert_includes %w[pre code span], element.name
        assert element.attributes.keys.all? { |name| name == 'class' }
      end
    end
  end

  def test_notes_and_long_lines_preserve_text
    source = "puts '#{'日本語' * 1000}'"
    document = slide("# Notes\n\n<!-- notes:\n```ruby\n#{source}\n```\n-->\n")
    html = REXML::Document.new(document.notes_html)
    assert_equal "#{source}\n", REXML::XPath.match(html, '//text()').map(&:value).join
    refute_includes document.html, 'highlight'
  end

  def test_rouge_is_loaded_only_for_a_language_tagged_block
    code = <<~'CODE'
      require 'wani/core/parser'
      parser = Wani::Core::Parser.new
      parser.parse("# Plain\n\n`code`\n\n```\nputs 1\n```\n")
      abort 'loaded too early' if defined?(Rouge)
      parser.parse("```ruby\nputs 1\n```\n")
      abort 'not loaded' unless defined?(Rouge)
    CODE
    out, status = Open3.capture2e('bundle', 'exec', 'ruby', '-Ilib', '-e', code)
    assert status.success?, out
  end
end
