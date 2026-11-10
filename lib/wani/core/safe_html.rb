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

      # Accept only an explicit, canonical YouTube video URL and numeric bounds.
      def self.youtube(value)
        return nil unless value.is_a?(String)
        match = value.match(%r{\Ahttps://(?:www\.)?youtube\.com/watch\?([^#]+)\z})
        return nil unless match
        pairs = match[1].split("&", -1).map { |part| part.split("=", 2) }
        return nil unless pairs.all? { |key, val| %w[v start end].include?(key) && val && !val.empty? }
        return nil unless pairs.map(&:first).uniq.length == pairs.length
        params = pairs.to_h
        return nil unless params["v"]&.match?(/\A[A-Za-z0-9_-]{11}\z/)
        return nil unless %w[start end].all? { |key| !params[key] || params[key].match?(/\A\d{1,8}\z/) }
        return nil if params["end"] && params["end"].to_i <= (params["start"] || "0").to_i
        params
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
          if (video = self.class.youtube(node.attr["src"]))
            id = video.fetch("v")
            query = %w[start end].filter_map { |key| "#{key}=#{video[key]}" if video[key] }.join("&")
            url = "https://www.youtube.com/embed/#{id}"
            url += "?#{query}" unless query.empty?
            alt = self.class.escape(node.attr["alt"])
            "<span class=\"youtube-video\" data-youtube-src=\"#{self.class.escape(url)}\"><img src=\"https://i.ytimg.com/vi/#{id}/hqdefault.jpg\" alt=\"#{alt}\"><button type=\"button\" class=\"youtube-play\" aria-label=\"#{alt.empty? ? 'YouTube動画を再生' : alt + 'を再生'}\">▶</button></span>"
          elsif self.class.safe_url?(node.attr["src"], image: true)
            alt = node.attr["alt"].to_s
            split = alt.match(/\Abg\s+(left|right)(?:\s+(.*))?\z/m)
            position = split ? " class=\"wani-image-#{split[1]}\"" : ""
            alt = split[2].to_s if split
            "<img#{position} src=\"#{self.class.escape(node.attr['src'])}\" alt=\"#{self.class.escape(alt)}\">"
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
