require "yaml"
require "cgi"
require "kramdown"
require "kramdown-parser-gfm"

module Preflight
  class Parser
    class Error < StandardError; end

    def parse(source)
      lines = source.gsub("\r\n", "\n").lines
      footer = ""
      if lines.first&.strip == "---"
        ending = (1...lines.length).find { |index| lines[index].strip == "---" }
        raise Error, "unclosed front matter" unless ending
        begin
          config = YAML.safe_load(lines[1...ending].join, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
        rescue Psych::Exception
          raise Error, "invalid front matter"
        end
        raise Error, "front matter must be a mapping" unless config.is_a?(Hash)
        raise Error, "footer must be a string" if config.key?("footer") && !config["footer"].is_a?(String)
        footer = config.fetch("footer", "")
        lines = lines[(ending + 1)..]
      end
      chunks = [""]
      fence = nil
      note_open = false
      lines.each do |line|
        if note_open
          note_open = false if line.include?("-->")
        elsif fence
          fence = nil if line.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.length},}[ \t]*\n?\z/)
        elsif (match = line.match(/\A {0,3}(`{3,}|~{3,})/))
          fence = match[1]
        elsif line.match?(/\A {0,3}<!--\s*notes:/)
          note_open = !line.include?("-->")
        elsif line.match?(/\A---[ \t]*\n?\z/)
          chunks << ""
          next
        end
        chunks.last << line
      end
      raise Error, "unclosed notes" if note_open
      warnings = []
      slides = chunks.each_with_index.map do |chunk, index|
        document = Kramdown::Document.new(chunk, input: "GFM", syntax_highlighter: nil)
        notes = []
        extract_notes(document.root, notes)
        headers = document.root.children.select { |node| node.type == :header }
        warnings << "slide #{index + 1}: additional heading" if headers.length > 1
        title = headers.first
        document.root.children.delete(title) if title
        {
          "title" => title ? plain(title) : "",
          "html" => render(document.root),
          "notes_html" => notes.map { |text| render(Kramdown::Document.new(text, input: "GFM").root) }.join,
          "images" => images(document.root)
        }
      end
      { "footer" => footer, "slides" => slides, "warnings" => warnings }
    end

    private

    def extract_notes(node, notes)
      node.children.delete_if do |child|
        if child.type == :xml_comment && child.value.match?(/\A<!--\s*notes:/)
          match = child.value.match(/\A<!--\s*notes:\s*(.*?)-->\s*\z/m)
          raise Error, "invalid notes" unless match
          notes << match[1]
          true
        else
          extract_notes(child, notes)
          false
        end
      end
    end

    def plain(node)
      node.type == :text || node.type == :codespan ? node.value : node.children.map { |child| plain(child) }.join
    end

    def images(node)
      found = node.type == :img && safe_url?(node.attr["src"], image: true) ? [node.attr["src"]] : []
      found + node.children.flat_map { |child| images(child) }
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def safe_url?(value, image: false)
      return false unless value.is_a?(String)
      return false if value.match?(/[\x00-\x20\x7f\\]/) || value.start_with?("//")
      scheme = value[/\A([^\/:?#]+):/, 1]
      !scheme || (image ? %w[http https] : %w[http https mailto]).include?(scheme.downcase)
    end

    def render(node)
      body = node.children.map { |child| render(child) }.join
      case node.type
      when :root then body
      when :text, :codespan, :codeblock
        text = escape(node.value)
        node.type == :codespan ? "<code>#{text}</code>" : node.type == :codeblock ? "<pre><code>#{text}</code></pre>" : text
      when :p, :em, :strong, :ul, :ol, :li, :blockquote
        "<#{node.type}>#{body}</#{node.type}>"
      when :header then "<h2>#{body}</h2>"
      when :a
        safe_url?(node.attr["href"]) ? "<a href=\"#{escape(node.attr['href'])}\">#{body}</a>" : body
      when :img
        safe_url?(node.attr["src"], image: true) ? "<img src=\"#{escape(node.attr['src'])}\" alt=\"#{escape(node.attr['alt'])}\">" : escape(node.attr["alt"])
      when :br then "<br>"
      when :hr then "<hr>"
      when :entity then escape(node.value.char)
      when :html_element, :xml_comment, :xml_pi then ""
      else body
      end
    end
  end
end
