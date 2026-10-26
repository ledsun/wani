require_relative "test_helper"
require "wani/core/parser"

class FooterTest < Minitest::Test
  def parse(source)
    Wani::Core::Parser.new.parse(source)
  end

  def test_default_override_empty_and_reset_to_default
    source = "---\nfooter: Default\n---\n# One\n\n---\n\n# Two\n\n<!-- footer: Specific -->\n\n---\n\n# Three\n\n<!-- footer: -->\n\n---\n\n# Four"
    document = parse(source)
    assert_equal %w[Default Specific] + ["", "Default"], document.slides.map(&:footer)
    assert_equal "Default", document.footer
    refute_includes document.slides[1].html, "Specific"
    assert_empty document.diagnostics
  end

  def test_multiline_duplicate_and_literal_html_are_text
    document = parse("# Title\n\n<!--\nfooter:\nFirst\n-->\n\n<!-- footer: <b>Last</b> -->")
    assert_equal "<b>Last</b>", document.slides[0].footer
    assert document.diagnostics.any? { |issue| issue.message.include?("Multiple footer") }
    refute_includes document.slides[0].html, "Last"
  end

  def test_code_and_notes_do_not_override_page_footer
    document = parse("# Title\n\n```md\n<!-- footer: Code -->\n```\n\n<!-- notes:\nfooter: Note text\n-->")
    assert_equal "", document.slides[0].footer
    assert_includes document.slides[0].html, "&lt;!-- footer: Code --&gt;"
    assert_includes document.slides[0].notes_html, "footer: Note text"
  end
end
