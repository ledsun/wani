require_relative "test_helper"
require "wani/core/parser"

class PageFootnoteTest < Minitest::Test
  def parse(source)
    Wani::Core::Parser.new.parse(source)
  end

  def test_only_page_footnotes_are_used
    source = "---\npage-footnote: Default\n---\n# One\n\n---\n\n# Two\n\n<!-- page-footnote: Specific -->\n\n---\n\n# Three\n\n<!-- page-footnote: -->\n\n---\n\n# Four"
    document = parse(source)
    assert_equal ["", "Specific", "", ""], document.slides.map(&:page_footnote)
    refute_includes document.to_h.keys, :page_footnote
    refute_includes document.slides[1].html, "Specific"
    assert_empty document.diagnostics
  end

  def test_multiline_duplicate_and_literal_html_are_text
    document = parse("# Title\n\n<!--\npage-footnote:\nFirst\n-->\n\n<!-- page-footnote: <b>Last</b> -->")
    assert_equal "<b>Last</b>", document.slides[0].page_footnote
    assert document.diagnostics.any? { |issue| issue.message.include?("Multiple page-footnote") }
    refute_includes document.slides[0].html, "Last"
  end

  def test_old_footer_comments_are_not_page_footnotes
    document = parse("# Title\n\n<!-- footer: Old name -->\n\n<!-- page-footnote: Source -->")
    assert_equal "Source", document.slides[0].page_footnote
    refute_includes document.slides[0].to_h.keys, :footer
    assert_equal "", parse("# Title\n\n<!-- footer: Old name -->").slides[0].page_footnote
  end

  def test_code_and_notes_do_not_override_page_footnote
    document = parse("# Title\n\n```md\n<!-- page-footnote: Code -->\n```\n\n<!-- notes:\npage-footnote: Note text\n-->")
    assert_equal "", document.slides[0].page_footnote
    assert_includes document.slides[0].html, "&lt;!-- page-footnote: Code --&gt;"
    assert_includes document.slides[0].notes_html, "page-footnote: Note text"
  end
end
