require "yaml"
require "kramdown"
require "kramdown-parser-gfm"
require_relative "presentation"
require_relative "safe_html"

module Wani
  module Core
    class Parser
      class Error < StandardError; end

      def parse(source)
        raise Error, "Markdown must be valid UTF-8" unless source.valid_encoding?
        lines = source.delete_prefix("\uFEFF").gsub("\r\n", "\n").lines
        config, lines = front_matter(lines)
        diagnostics = []
        chunks = split_slides(lines, diagnostics)
        slides = chunks.each_with_index.map do |chunk, index|
          number = index + 1
          warn = ->(message) { diagnostics << Diagnostic.new(severity: :warning, message: message, slide: number) }
          warn.call("Empty slide between separators") if chunk.strip.empty? && chunks.length > 1
          document = markdown(chunk)
          metadata = { "notes" => [], "footer" => [] }
          extract_metadata(document.root, metadata)
          notes = metadata.fetch("notes")
          footers = metadata.fetch("footer")
          warn.call("Multiple notes blocks combined") if notes.length > 1
          warn.call("Multiple footer blocks: the last value is used") if footers.length > 1
          headings = walk(document.root).select { |node| node.type == :header }
          warn.call("Additional heading: only the first heading is the slide title") if headings.length > 1
          title = headings.first
          raise Error, "Slide #{number}: title is empty" if title && plain(title).strip.empty?
          remove(document.root, title) if title
          renderer = SafeHTML.new(&warn)
          note_roots = notes.map { |text| markdown(text).root }
          Slide.new(number: number, title: title ? plain(title) : "", html: renderer.render(document.root),
            footer: footers.empty? ? config.fetch("footer", "") : footers.last.strip,
            notes_html: note_roots.map { |root| renderer.render(root) }.join,
            images: ([document.root] + note_roots).flat_map { |root| walk(root).select { |node| node.type == :img && SafeHTML.safe_url?(node.attr['src'], image: true) }.map { |node| node.attr['src'] } }.uniq)
        end
        Presentation.new(slides: slides, footer: config.fetch("footer", ""), decorations: config.fetch("decorations", true), time_limit: config.fetch("time_limit", 5), diagnostics: diagnostics.uniq { |item| item.to_h })
      rescue Encoding::CompatibilityError, ArgumentError => error
        raise Error, "Invalid Markdown: #{error.message}"
      end

      private

      def front_matter(lines)
        return [{}, lines] unless lines.first&.strip == "---"
        ending = (1...lines.length).find { |index| lines[index].strip == "---" }
        raise Error, "Unclosed Front Matter" unless ending
        config = YAML.safe_load(lines[1...ending].join, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
        raise Error, "Front Matter must be a mapping" unless config.is_a?(Hash)
        raise Error, "footer must be a string" if config.key?("footer") && !config["footer"].is_a?(String)
        raise Error, "decorations must be true or false" if config.key?("decorations") && ![true, false].include?(config["decorations"])
        if config.key?("time_limit")
          limit = config["time_limit"]
          raise Error, "time_limit must be a finite non-negative number of minutes" unless limit.is_a?(Numeric) && limit.finite? && limit >= 0 && (limit * 60_000).finite?
        end
        [config, lines[(ending + 1)..]]
      rescue Psych::Exception
        raise Error, "Invalid or unsafe YAML in Front Matter"
      end

      def split_slides(lines, diagnostics)
        chunks = [+""]
        fence = nil
        comment = false
        lines.each do |line|
          if comment
            comment = false if line.include?("-->")
          elsif fence
            fence = nil if line.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.length},}[ \t]*\n?\z/)
          elsif (match = line.match(/\A {0,3}(`{3,}|~{3,})/))
            fence = match[1]
          elsif line.match?(/\A {0,3}<!--/)
            comment = !line.include?("-->")
          elsif line.match?(/\A {0,3}---[ \t]*\n?\z/)
            chunks << +""
            next
          elsif line.match?(/\A {0,3}[#]{1,6}[ \t]*\n?\z/)
            raise Error, "Slide #{chunks.length}: title is empty"
          end
          chunks.last << line
        end
        raise Error, "Unclosed comment or notes block" if comment
        diagnostics << Diagnostic.new(severity: :warning, message: "Unclosed code fence", slide: chunks.length) if fence
        chunks
      end

      def markdown(text)
        Kramdown::Document.new(text, input: "GFM", syntax_highlighter: nil)
      end

      def extract_metadata(node, metadata)
        node.children.delete_if do |child|
          if child.type == :xml_comment && child.value.match?(/\A<!--\s*(notes|footer):/)
            match = child.value.match(/\A<!--\s*(notes|footer):\s*(.*?)-->\s*\z/m)
            raise Error, "Invalid slide metadata block" unless match
            metadata.fetch(match[1]) << match[2]
            true
          else
            extract_metadata(child, metadata)
            false
          end
        end
      end

      def walk(node)
        [node] + node.children.flat_map { |child| walk(child) }
      end

      def remove(node, target)
        node.children.delete(target)
        node.children.each { |child| remove(child, target) }
      end

      def plain(node)
        case node.type
        when :text, :codespan then node.value
        when :entity then node.value.char
        when :smart_quote then SafeHTML::QUOTES.fetch(node.value, "")
        else node.children.map { |child| plain(child) }.join
        end
      end
    end
  end
end
