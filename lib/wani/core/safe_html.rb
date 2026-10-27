module Wani
  module Core
    # Emit only known Markdown elements; never forward raw HTML or arbitrary attributes.
    class SafeHTML
      TAGS = { p: "p", em: "em", strong: "strong", ul: "ul", ol: "ol", li: "li", blockquote: "blockquote", header: "h2", table: "table", thead: "thead", tbody: "tbody", tr: "tr", th: "th", td: "td", del: "del" }.freeze
      QUOTES = { lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”" }.freeze
      def self.escape(value)
        value.to_s.gsub(/[&<>"']/) { |character| { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&#39;" }.fetch(character) }
      end

      def self.safe_url?(value, image: false)
        return false unless value.is_a?(String) && !value.empty?
        return false if value.match?(/[\x00-\x20\x7f\\]/) || value.start_with?("//")
        return false if value.match?(/&(?:#\d+|#x[0-9a-f]+|[a-z]+);/i)
        scheme = value[/\A([^\/:?#]+):/, 1]
        !scheme || (image ? %w[http https] : %w[http https mailto]).include?(scheme.downcase)
      end

      def initialize(&diagnostic)
        @diagnostic = diagnostic || ->(_message) {}
      end

      def render(node)
        body = node.children.map { |child| render(child) }.join
        tag = TAGS[node.type]
        return "<#{tag}>#{body}</#{tag}>" if tag
        case node.type
        when :root then body
        when :text then self.class.escape(node.value)
        when :codespan then "<code>#{self.class.escape(node.value)}</code>"
        when :codeblock then codeblock(node)
        when :a
          if self.class.safe_url?(node.attr["href"])
            "<a href=\"#{self.class.escape(node.attr['href'])}\" rel=\"noopener noreferrer\">#{body}</a>"
          else
            @diagnostic.call("Unsafe link URL removed")
            body
          end
        when :img
          if self.class.safe_url?(node.attr["src"], image: true)
            "<img src=\"#{self.class.escape(node.attr['src'])}\" alt=\"#{self.class.escape(node.attr['alt'])}\">"
          else
            @diagnostic.call("Unsafe image URL removed")
            self.class.escape(node.attr["alt"])
          end
        when :br then "<br>"
        when :hr then "<hr>"
        when :entity then self.class.escape(node.value.char)
        when :smart_quote then QUOTES.fetch(node.value, "")
        when :html_element, :xml_pi
          @diagnostic.call("Raw HTML removed")
          ""
        when :xml_comment then ""
        else body
        end
      end

      private

      def codeblock(node)
        language = node.options[:lang]
        if language && !language.empty?
          require "rouge"
          lexer = Rouge::Lexer.find(language)
          if lexer
            html = Rouge::Formatters::HTML.new.format(lexer.new.lex(node.value))
            return "<pre class=\"highlight\"><code>#{html}</code></pre>"
          end
        end
        "<pre><code>#{self.class.escape(node.value)}</code></pre>"
      end
    end
  end
end
