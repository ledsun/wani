module Wani
  module Browser
    class Layout
      WIDTH = 1920
      HEIGHT = 1080
      BODY_MIN = 16
      BODY_MAX = 160
      COVER_BODY_SIZE = 48
      TITLE_MIN = 24
      TITLE_MAX = 220
      NO_WRAP_EMS = 20
      TABLE_NO_WRAP_EMS = 15
      TITLE_GAP_MAX = 64

      def initialize(document, &warn)
        @document, @warn = document, warn
      end

      def wait_assets(root)
        unless @fonts_loaded
          # Hidden slide titles and code do not trigger font downloads. Load both
          # bundled families and weights explicitly before fitting.
          body_family = JS.global.getComputedStyle(@document[:documentElement])[:fontFamily].to_s
          [body_family, '"UDEV Gothic"'].each do |family|
            [400, 700].each do |weight|
              begin
                @document[:fonts].load("#{weight} 16px #{family}", "日本語 ABC").await
              rescue JS::Error
                @warn.call("フォントを読み込めませんでした。代替フォントを使用します (#{weight})")
              end
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
        title[:style][:transform] = ""
        unless title[:style][:display].to_s == "none"
          fit_font(title, TITLE_MIN, TITLE_MAX)
          @warn.call("スライド #{number}: タイトルが収まりません: #{title[:textContent]}") unless fits?(title)
        end
        body = section.querySelector(".body")
        body[:style][:marginTop] = ""
        body.querySelectorAll("colgroup[data-wani-columns]").to_a.each(&:remove)
        prepare_wrapping(body)
        fit_images(body)
        tables = body.querySelectorAll("table").to_a
        cover = section[:classList].contains("cover") == JS::True
        if cover
          body[:style][:fontSize] = "#{COVER_BODY_SIZE}px"
          if tables.any? { |table| table_overflows?(table) }
            fit_font(body, BODY_MIN, COVER_BODY_SIZE) { tables.none? { |table| table_overflows?(table) } }
          end
        else
          fit_font(body, BODY_MIN, BODY_MAX) { body_fits?(body, tables) }
        end
        overflowing_tables = tables.select { |table| table_overflows?(table) }
        overflowing_tables.each do |table|
          table.querySelectorAll("th [data-wani-line], td [data-wani-line]").to_a.each do |line|
            line[:style][:whiteSpace] = "normal"
          end
        end
        unless cover || overflowing_tables.empty?
          fit_font(body, BODY_MIN, BODY_MAX) { body_fits?(body, tables) }
        end
        tables.each { |table| distribute_table_space(table) }
        add_title_gap(section, title, body, tables) unless cover
        body_fits = if cover
          cover_body_fits?(body)
        else
          body_fits?(body, tables)
        end
        @warn.call("スライド #{number}: 本文が収まりません: #{body[:textContent].to_s[0, 120]}") unless body_fits
        if section[:classList].contains("multiline-title") == JS::True
          title_rect = title.getBoundingClientRect
          body_top = body[:children].to_a.map { |child| child.getBoundingClientRect[:top].to_f }.min
          if body_top
            scale = section.getBoundingClientRect[:width].to_f / WIDTH
            shift = (title_rect[:bottom].to_f + 36 * scale - body_top) / scale
            title[:style][:transform] = "translateY(-#{shift}px)" if shift.positive?
          end
        end
        if section[:classList].contains("cover") == JS::True && title[:style][:display].to_s != "none"
          title_rect = title.getBoundingClientRect
          overlap = body[:children].to_a.any? do |child|
            rect = child.getBoundingClientRect
            rect[:top].to_f < title_rect[:bottom].to_f && rect[:bottom].to_f > title_rect[:top].to_f &&
              rect[:left].to_f < title_rect[:right].to_f && rect[:right].to_f > title_rect[:left].to_f
          end
          @warn.call("スライド #{number}: タイトルと本文が重なっています") if overlap
        end
        footnote = section.querySelector(".page-footnote")
        if footnote[:scrollWidth].to_i > footnote[:clientWidth].to_i + 1
          @warn.call("スライド #{number}: 脚注が1行に収まりません。短くするか、詳細を本文へ移してください。")
        end
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

      def add_title_gap(section, title, body, tables)
        return if title[:style][:display].to_s == "none" || body[:children].to_a.empty? || !body_fits?(body, tables)
        scale = section.getBoundingClientRect[:width].to_f / WIDTH
        return if scale <= 0
        bottom = body[:children].to_a.map { |child| child.getBoundingClientRect[:bottom].to_f }.max
        spare = (body.getBoundingClientRect[:bottom].to_f - bottom) / scale
        gap = [[spare * 0.2, TITLE_GAP_MAX].min, 0].max
        body[:style][:marginTop] = "#{gap}px"
        body[:style][:marginTop] = "" unless body_fits?(body, tables)
      end

      def prepare_wrapping(body)
        # Rebuild the wrappers when a slide is fitted again (for example after
        # editing). Ranges preserve links, emphasis and explicit line breaks.
        body.querySelectorAll("[data-wani-line]").to_a.each do |line|
          line.replaceWith(*line[:childNodes].to_a)
        end
        body[:style][:fontSize] = "#{BODY_MIN}px"
        body.querySelectorAll("p, h1, h2, h3, h4, h5, h6, li, th, td").to_a.each do |block|
          cell = %w[TH TD].include?(block[:tagName].to_s)
          nested_blocks = cell ? "p, h1, h2, h3, h4, h5, h6, ul, ol, pre, table" : "p, ul, ol"
          next unless block.querySelector(nested_blocks) == JS::Null
          threshold = cell ? TABLE_NO_WRAP_EMS : NO_WRAP_EMS
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
            reference[:textContent] = "あ" * threshold
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

      def table_overflows?(table)
        table[:offsetWidth].to_i > table[:parentElement][:clientWidth].to_i
      end

      def distribute_table_space(table)
        return unless table.querySelector(":scope > colgroup") == JS::Null
        rows = table[:rows].to_a
        return if rows.empty?
        cells = rows.first[:cells].to_a
        return if cells.length < 2
        return unless rows.all? do |row|
          row_cells = row[:cells].to_a
          row_cells.length == cells.length &&
            row_cells.all? { |cell| cell[:colSpan].to_i == 1 && cell[:rowSpan].to_i == 1 }
        end

        available = table.getBoundingClientRect[:width].to_f
        style = table[:style]
        original = style[:cssText].to_s
        style[:width] = "max-content"
        style[:maxWidth] = "none"
        spare = available - table.getBoundingClientRect[:width].to_f
        widths = cells.map { |cell| cell.getBoundingClientRect[:width].to_f }
        style[:cssText] = original
        return unless spare.positive?

        widths.map! { |width| width + spare / cells.length }
        total = widths.sum
        columns = @document.createElement("colgroup")
        columns.setAttribute("data-wani-columns", "")
        widths.each do |width|
          column = @document.createElement("col")
          column[:style][:width] = "#{100 * width / total}%"
          columns.appendChild(column)
        end
        first_section = table.querySelector(":scope > thead, :scope > tbody, :scope > tfoot, :scope > tr")
        table.insertBefore(columns, first_section)
      end

      def fits?(node)
        node[:scrollWidth].to_i <= node[:clientWidth].to_i + 1 && node[:scrollHeight].to_i <= node[:clientHeight].to_i + 1
      end

      def body_fits?(body, tables)
        return false unless fits?(body)
        return true if tables.empty?

        # Integer scroll heights can hide a clipped table border.
        bottom = body.getBoundingClientRect[:bottom].to_f
        tables.all? { |table| table.getBoundingClientRect[:bottom].to_f <= bottom }
      end

      def cover_body_fits?(body)
        bounds = body.getBoundingClientRect
        body[:scrollWidth].to_i <= body[:clientWidth].to_i + 1 && body[:children].to_a.all? do |child|
          rect = child.getBoundingClientRect
          rect[:top].to_f >= bounds[:top].to_f - 1 && rect[:bottom].to_f <= bounds[:bottom].to_f + 1 &&
            rect[:left].to_f >= bounds[:left].to_f - 1 && rect[:right].to_f <= bounds[:right].to_f + 1
        end
      end

      def fit_font(node, minimum, maximum)
        low, high, best = minimum, maximum, minimum
        while low <= high
          middle = (low + high) / 2
          node[:style][:fontSize] = "#{middle}px"
          if block_given? ? yield : fits?(node)
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
        content = body.cloneNode(true)
        content.querySelectorAll(".youtube-video").to_a.each(&:remove)
        mixed = !content[:textContent].to_s.strip.empty?
        videos_only = images.all? { |image| image.closest(".youtube-video") != JS::Null }
        fraction = mixed ? 0.45 : (videos_only ? 0.98 : 0.85)
        columns = body[:classList].contains("image-columns") == JS::True
        budget = body[:clientHeight].to_f * (columns ? 0.95 : fraction) / images.length
        images.each do |image|
          next if image[:naturalWidth].to_i.zero? || image[:naturalHeight].to_i.zero?
          width = image[:naturalWidth].to_f
          height = image.closest(".youtube-video") == JS::Null ? image[:naturalHeight].to_f : width * 9 / 16
          available_width = body[:clientWidth].to_f * (columns ? 0.47 : 1.0)
          ratio = [available_width / width, budget / height].min
          image[:style][:width] = "#{width * ratio}px"
          image[:style][:height] = "#{height * ratio}px"
        end
      end
    end
  end
end
