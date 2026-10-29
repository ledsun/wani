module Wani
  module Browser
    class Layout
      WIDTH = 1920
      HEIGHT = 1080
      BODY_MIN = 16
      BODY_MAX = 160
      TITLE_MIN = 24
      TITLE_MAX = 220
      NO_WRAP_EMS = 20

      def initialize(document, &warn)
        @document, @warn = document, warn
      end

      def wait_assets(root)
        unless @fonts_loaded
          # Hidden slide titles do not trigger font downloads. Load both weights
          # explicitly before fitting, including Japanese glyphs in the request.
          family = JS.global.getComputedStyle(@document[:documentElement])[:fontFamily].to_s
          [400, 700].each do |weight|
            begin
              @document[:fonts].load("#{weight} 16px #{family}", "日本語 ABC").await
            rescue JS::Error
              @warn.call("フォントを読み込めませんでした。代替フォントを使用します (#{weight})")
            end
          end
          @fonts_loaded = true
        end
        @document[:fonts][:ready].await
        root.querySelectorAll("img").to_a.each do |image|
          unless image[:complete] == JS::True
            JS.global[:Promise].new do |resolve, _reject|
              settled = false
              finish = -> do
                unless settled
                  settled = true
                  resolve.apply(nil)
                end
                nil
              end
              image.addEventListener("load", ->(_event) { finish.call }, { once: true }.to_js)
              image.addEventListener("error", ->(_event) { finish.call }, { once: true }.to_js)
              JS.global.setTimeout(-> { finish.call }, 15_000)
            end.await
          end
          @warn.call("画像の読み込みに失敗しました: #{image.getAttribute('src')}") if image[:naturalWidth].to_i.zero?
        end
      end

      def fit_slide(section, number)
        section[:style][:display] = "flex"
        title = section.querySelector(".title")
        unless title[:style][:display].to_s == "none"
          fit_font(title, TITLE_MIN, TITLE_MAX)
          @warn.call("スライド #{number}: タイトルが収まりません: #{title[:textContent]}") unless fits?(title)
        end
        body = section.querySelector(".body")
        prepare_wrapping(body)
        fit_images(body)
        fit_font(body, BODY_MIN, BODY_MAX)
        @warn.call("スライド #{number}: 本文が収まりません: #{body[:textContent].to_s[0, 120]}") unless fits?(body)
        section[:style][:display] = ""
      end

      def scale
        viewport = @document.getElementById("viewport")
        style = JS.global.getComputedStyle(viewport)
        width = viewport[:clientWidth].to_f - style[:paddingLeft].to_s.to_f - style[:paddingRight].to_s.to_f
        height = viewport[:clientHeight].to_f - style[:paddingTop].to_s.to_f - style[:paddingBottom].to_s.to_f
        ratio = [width / WIDTH, height / HEIGHT].min
        @document.getElementById("stage")[:style][:transform] = "scale(#{[ratio, 0.01].max})"
      end

      private

      def prepare_wrapping(body)
        # Rebuild the wrappers when a slide is fitted again (for example after
        # editing). Ranges preserve links, emphasis and explicit line breaks.
        body.querySelectorAll("[data-wani-line]").to_a.each do |line|
          line.replaceWith(*line[:childNodes].to_a)
        end
        body[:style][:fontSize] = "#{BODY_MIN}px"
        body.querySelectorAll("p, h1, h2, h3, h4, h5, h6, li").to_a.each do |block|
          next unless block.querySelector("p, ul, ol") == JS::Null
          breaks = block.querySelectorAll("br").to_a
          # Work backwards so extracting a range does not invalidate the next.
          (0..breaks.length).to_a.reverse_each do |index|
            range = @document.createRange
            range.selectNodeContents(block)
            range.setStartAfter(breaks[index - 1]) if index.positive?
            range.setEndBefore(breaks[index]) if index < breaks.length
            line = @document.createElement("span")
            line.setAttribute("data-wani-line", "")
            line[:style][:whiteSpace] = "nowrap"
            line.appendChild(range.extractContents)
            range.insertNode(line)

            reference = @document.createElement("span")
            reference[:textContent] = "あ" * NO_WRAP_EMS
            reference[:style][:position] = "absolute"
            reference[:style][:whiteSpace] = "nowrap"
            block.appendChild(reference)
            if line.getBoundingClientRect[:width].to_f > reference.getBoundingClientRect[:width].to_f + 0.01
              line[:style][:whiteSpace] = "normal"
            end
            reference.remove
          end
        end
      end

      def fits?(node)
        node[:scrollWidth].to_i <= node[:clientWidth].to_i + 1 && node[:scrollHeight].to_i <= node[:clientHeight].to_i + 1
      end

      def fit_font(node, minimum, maximum)
        low, high, best = minimum, maximum, minimum
        while low <= high
          middle = (low + high) / 2
          node[:style][:fontSize] = "#{middle}px"
          if fits?(node)
            best, low = middle, middle + 1
          else
            high = middle - 1
          end
        end
        node[:style][:fontSize] = "#{best}px"
      end

      def fit_images(body)
        images = body.querySelectorAll("img").to_a
        return if images.empty?
        mixed = !body[:textContent].to_s.strip.empty?
        budget = body[:clientHeight].to_f * (mixed ? 0.45 : 0.85) / images.length
        images.each do |image|
          next if image[:naturalWidth].to_i.zero? || image[:naturalHeight].to_i.zero?
          ratio = [body[:clientWidth].to_f / image[:naturalWidth].to_f, budget / image[:naturalHeight].to_f].min
          image[:style][:width] = "#{image[:naturalWidth].to_f * ratio}px"
          image[:style][:height] = "#{image[:naturalHeight].to_f * ratio}px"
        end
      end
    end
  end
end
