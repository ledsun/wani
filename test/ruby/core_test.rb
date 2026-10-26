require_relative "test_helper"
require "wani/core/parser"
require "wani/core/validator"

class CoreTest < Minitest::Test
  def parse(source)
    Wani::Core::Parser.new.parse(source)
  end

  def test_time_limit_defaults_and_validates_minutes
    assert_equal 5, parse("# Default").time_limit
    [0, 1, 2.5].each do |limit|
      assert_equal limit, parse("---\ntime_limit: #{limit}\n---\n# Timer").time_limit
    end
    ['-1', 'true', '"5"', '.inf', '.nan', '[]'].each do |limit|
      assert_raises(Wani::Core::Parser::Error) { parse("---\ntime_limit: #{limit}\n---\n# Invalid") }
    end
  end

  def test_metadata_titles_notes_and_page_footnote
    document = parse("# **One** &amp; two\n\n<!-- page-footnote: Footnote -->\n\nBody\n\n<!--\nnotes:\nPrivate **note**\n-->\n\n---\n\n###### Last")
    assert_equal "Footnote", document.slides[0].page_footnote
    refute_includes document.to_h.keys, :decorations
    assert_equal ["One & two", "Last"], document.slides.map(&:title)
    assert_includes document.slides[0].notes_html, "<strong>note</strong>"
    refute_includes document.slides[0].html, "Private"
    refute_includes document.slides[0].html, "<h"
  end

  def test_separators_inside_code_and_notes_do_not_split
    source = "# Code\n\n```md\n---\n<!-- notes: literal -->\n```\n\n~~~\n---\n~~~\n\n    ---\n\n<!--\nnotes:\nBefore\n\n---\n\nAfter\n-->\n\n---\n\nLast"
    document = parse(source)
    assert_equal 2, document.slides.length
    assert_includes document.slides[0].html, "&lt;!-- notes: literal --&gt;"
    assert_includes document.slides[0].notes_html, "<hr>"
  end

  def test_unsafe_yaml_and_unclosed_structures_are_rejected
    ["---\npage-footnote: !ruby/object:Object {}\n---", "---\na: &a x\npage-footnote: *a\n---", "---\npage-footnote: [broken\n---", "---\npage-footnote: x", "# Title\n\n<!--\nnotes: never closed", "#\n"].each do |source|
      assert_raises(Wani::Core::Parser::Error) { parse(source) }
    end
  end

  def test_titleless_empty_and_additional_headings
    assert_equal "", parse("").slides[0].title
    assert_equal 1, parse("").slides.length
    document = parse("# One\n\n## Two\n\n---\n\n---\n\nEnd")
    assert_equal 3, document.slides.length
    assert document.diagnostics.any? { |item| item.message.include?("Additional heading") }
    assert document.diagnostics.any? { |item| item.message.include?("Empty slide") }
  end

  def test_html_and_unsafe_urls_are_not_forwarded
    document = parse('# Safe' + "\n\n<script>alert(1)</script>\n\n<img src=x onerror=alert(2)>\n\n[bad](javascript:alert) [entity](jav&#x61;script:alert) ![bad](data:image/png,evil) [safe](https://example.com)")
    html = document.slides[0].html
    refute_match(/<script|<img[^>]+onerror|javascript:|data:image/, html)
    assert_includes html, 'href="https://example.com"'
    assert document.diagnostics.any?
  end

  def test_images_and_validator
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "a b.svg"), "<svg/>")
      document = parse("![ok](a%20b.svg)\n\n![missing](missing.png)\n\n<!-- notes: ![also missing](note.webp) -->")
      assert_equal %w[a%20b.svg missing.png note.webp], document.slides[0].images
      errors = Wani::Core::Validator.new.validate(document, base_dir: directory)
      assert_equal 2, errors.length
      assert errors.all? { |item| item.severity == :error }
    end
  end

  def test_check_exit_codes
    require "wani/cli"
    Dir.mktmpdir do |directory|
      file = File.join(directory, "slides.md")
      cli = Wani::CLI.new(out: StringIO.new, err: StringIO.new)
      File.write(file, "# Valid")
      assert_equal 0, cli.run(["check", file])
      File.write(file, "# Warnings\n\n## Extra")
      assert_equal 0, cli.run(["check", file])
      File.write(file, "![Missing](missing.svg)")
      assert_equal 1, cli.run(["check", file])
      File.write(file, "---\npage-footnote: [broken\n---")
      assert_equal 1, cli.run(["check", file])
    end
  end
end
