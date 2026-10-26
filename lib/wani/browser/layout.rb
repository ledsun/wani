module Wani
  module Browser
    class Layout
      WIDTH = 1920
      HEIGHT = 1080
      BODY_MIN = 16
      BODY_MAX = 160
      TITLE_MIN = 24
      TITLE_MAX = 220

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
