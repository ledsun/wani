require "js"
require "json"
require_relative "../core/parser"
require_relative "layout"
require_relative "renderer"
require_relative "fonts"
require_relative "presentation_timer"

module Wani
  module Browser
    class Application
      def start
        @document = JS.global[:document]
        @index = 0
        @warnings = []
        @layout = Layout.new(@document) { |message| warn(message) }
        @presentation = fetch_presentation
        render_presentation
        prepare_timer_image
        bind_events
        @waiting_to_start = JS.global[:location][:hash].to_s.empty?
        go(hash_index)
        %w[previous next fullscreen speaker print print-notes reload-slides pointer-character-toggle].each { |id| element(id)[:disabled] = false }
        update_buttons
        if @waiting_to_start
          element("start-overlay")[:hidden] = false
          element("viewport")[:inert] = true
          element("start-presentation").focus
        end
        element("status")[:textContent] = "準備できました"
      end

      private

      def fetch_presentation
        response = JS.global.fetch("/talk/slides.md", { cache: "no-store" }.to_js).await
        raise "Markdown を読み込めません (HTTP #{response[:status].to_i})" unless response[:ok] == JS::True
        Core::Parser.new.parse(response.text.await.to_s)
      end

      def render_presentation
        @warnings = []
        element("warnings")[:hidden] = true
        element("warnings")[:textContent] = ""
        @document.querySelectorAll('[data-wani-font]').to_a.each(&:remove)
        title = @presentation.slides.first.title
        @document[:title] = title.empty? ? "WANI — Markdown presentation" : title
        @presentation.diagnostics.each { |item| warn("#{item.slide ? "スライド #{item.slide}: " : ""}#{item.message}") }
        @renderer = Renderer.new(@document, @presentation)
        @sections = @presentation.slides.map { |slide| @renderer.slide(slide) }
        element("stage").replaceChildren
        @sections.each { |section| element("stage").appendChild(section) }
        font_sections = @sections + @presentation.slides.map { |slide| @renderer.slide(slide, notes: true) }
        Fonts.new(@document) { |message| warn(message) }.apply(@presentation.fonts, font_sections)
        @layout.wait_assets(element("stage"))
        @sections.each_with_index { |section, index| @layout.fit_slide(section, index + 1) }
        prepare_pages(false)
      end

      def reload_slides
        element("reload-slides")[:disabled] = true
        element("status")[:textContent] = "スライドを再読み込みしています…"
        presentation = fetch_presentation
        @presentation = presentation
        render_presentation
        prepare_timer_image if @waiting_to_start
        @active_number = nil
        # The start dialog remains open when the presentation has not started.
        go(@index)
        element("status")[:textContent] = "スライドを再読み込みしました"
      rescue => error
        warn("スライドを再読み込みできませんでした: #{error.message}")
        element("status")[:textContent] = "スライドの再読み込みに失敗しました"
      ensure
        element("reload-slides")[:disabled] = false
      end

      def element(id)
        @document.getElementById(id)
      end

      def warn(message)
        @warnings << message unless @warnings.include?(message)
        element("warnings")[:hidden] = false
        element("warnings")[:textContent] = @warnings.join("\n")
      end

      def async(&block)
        Fiber.new do
          block.call
        rescue => error
          warn(error.message)
        end.transfer
      end

      def bind_events
        element("start-presentation").addEventListener("click") do
          next unless @waiting_to_start
          @waiting_to_start = false
          element("start-overlay")[:hidden] = true
          element("viewport")[:inert] = false
          element("start-presentation").blur
          go(0)
          @started_at = JS.global[:Date].now.to_f
          @elapsed_callback = -> { update_speaker_elapsed }
          JS.global.setInterval(@elapsed_callback, 1000)
          update_speaker_elapsed
          start_timer
        end
        element("previous").addEventListener("click") { go(@index - 1) }
        element("next").addEventListener("click") { go(@index + 1) }
        element("reload-slides").addEventListener("click") { async { reload_slides } }
        element("fullscreen").addEventListener("click") { fullscreen }
        element("speaker").addEventListener("click") { speaker }
        bind_pointer_character
        JS.global.addEventListener("message") do |event|
          next unless @speaker && event[:origin].to_s == JS.global[:location][:origin].to_s && event[:source] == @speaker && event[:data].to_s == "wani-speaker-ready"
          connect_speaker
        end
        element("print").addEventListener("click") { async { print_pages(false) } }
        element("print-notes").addEventListener("click") { async { print_pages(true) } }
        @document.addEventListener("keydown") do |event|
          target = event[:target]
          next if event[:ctrlKey] == JS::True || event[:altKey] == JS::True || event[:metaKey] == JS::True
          next if %w[INPUT TEXTAREA SELECT].include?(target[:tagName].to_s) || target[:isContentEditable] == JS::True
          next if @waiting_to_start && !%w[f F Escape n N c C].include?(event[:key].to_s)
          if event[:key].to_s == "Escape"
            close = @sections[@index].querySelector(".youtube-close")
            unless close == JS::Null
              close.click
              event.preventDefault
              next
            end
          end
          handled = true
          case event[:key].to_s
          when "ArrowRight", " ", "PageDown" then go(@index + 1)
          when "ArrowLeft", "PageUp" then go(@index - 1)
          when "Home" then go(0)
          when "End" then go(@sections.length - 1)
          when "f", "F" then fullscreen
          when "Escape" then exit_fullscreen
          when "n", "N" then speaker
          when "c", "C" then toggle_pointer_character unless event[:repeat] == JS::True
          else handled = false
          end
          event.preventDefault if handled
        end
        JS.global.addEventListener("resize") { @layout.scale }
        JS.global.addEventListener("hashchange") { go(hash_index) }
        @document.addEventListener("fullscreenchange") { @layout.scale }
      end

      def bind_pointer_character
        @pointer_enabled = false
        @pointer_seen = false
        @pointer_direction = 1
        element("pointer-character-toggle").addEventListener("click") { toggle_pointer_character }
        @document.addEventListener("mousemove") do |event|
          next unless @pointer_enabled
          @pointer_target_x, @pointer_target_y = event[:clientX].to_f, event[:clientY].to_f
          unless @pointer_seen
            @pointer_x, @pointer_y = @pointer_target_x, @pointer_target_y
            @pointer_seen = true
            element("pointer-character")[:hidden] = false
            @pointer_animation.call
          end
        end
        @document.addEventListener("mouseleave") do
          @pointer_seen = false
          element("pointer-character")[:hidden] = true
          JS.global.cancelAnimationFrame(@pointer_frame) if @pointer_frame
        end
        @pointer_animation = ->(_time = nil) do
          if @pointer_enabled && @pointer_seen
            distance_x = @pointer_target_x - @pointer_x
            @pointer_direction = distance_x.positive? ? 1 : -1 if distance_x.abs > 1
            @pointer_x += (@pointer_target_x - @pointer_x) * 0.08
            @pointer_y += (@pointer_target_y - @pointer_y) * 0.08
            element("pointer-character")[:style][:transform] = "translate(#{@pointer_x - 40}px, #{@pointer_y - 19}px) scaleX(#{@pointer_direction})"
            @pointer_frame = JS.global.requestAnimationFrame(@pointer_animation)
          end
        end
      end

      def toggle_pointer_character
        @pointer_enabled = !@pointer_enabled
        @pointer_seen = false
        JS.global.cancelAnimationFrame(@pointer_frame) if @pointer_frame
        element("pointer-character")[:hidden] = true
        element("pointer-character-toggle").setAttribute("aria-pressed", @pointer_enabled.to_s)
      end

      def hash_index
        match = JS.global[:location][:hash].to_s.match(/\A#slide=(\d+)\z/)
        match ? match[1].to_i - 1 : 0
      end

      def go(index)
        return if @waiting_to_start && @active_number

        if @time_expired
          @time_expired = false
          element("time-expired")[:hidden] = true
          element("viewport")[:inert] = false
          index = @index
        end
        previous_number = @active_number || 0
        @index = index.clamp(0, @sections.length - 1)
        if previous_number.positive? && previous_number != @index + 1
          @sections[previous_number - 1].querySelectorAll(".youtube-overlay").to_a.each(&:remove)
        end
        @renderer.transition(@sections[@index], previous_number)
        @sections.each_with_index { |section, number| section[:classList].toggle("active", number == @index) }
        @active_number = @index + 1
        element("position")[:textContent] = "#{@index + 1} / #{@sections.length}"
        desired = "#slide=#{@index + 1}"
        JS.global[:history].replaceState(JS::Null, "", desired) unless @waiting_to_start || JS.global[:location][:hash].to_s == desired
        update_buttons
        @layout.scale
        sync_speaker
        update_timer_for_slide
      end

      def update_buttons
        element("previous")[:disabled] = @index.zero? && !@time_expired
        element("next")[:disabled] = @index == @sections.length - 1 && !@time_expired
      end

      def fullscreen
        return exit_fullscreen unless @document[:fullscreenElement] == JS::Null
        @document[:documentElement].requestFullscreen.then(->(_value) { nil }, ->(_error) { warn("全画面表示が許可されませんでした。F またはボタンから再試行してください。"); nil })
      end

      def exit_fullscreen
        return if @document[:fullscreenElement] == JS::Null
        @document.exitFullscreen.then(->(_value) { nil }, ->(_error) { warn("全画面表示を終了できませんでした"); nil })
      end

      def speaker
        if @speaker && @speaker[:closed] == JS::False
          @speaker.focus
          sync_speaker
          return
        end
        @speaker = JS.global.open("/assets/speaker.html", "wani-speaker")
        if @speaker == JS::Null
          warn("ノート画面を開けません。ポップアップを許可して再試行してください。")
          return
        end
      end

      def connect_speaker
        @speaker.addEventListener("message") do |event|
          next unless event[:origin].to_s == JS.global[:location][:origin].to_s && event[:source] == JS.global
          state = JSON.parse(event[:data].to_s)
          document = @speaker[:document]
          document.getElementById("position")[:textContent] = state.fetch("position")
          document.getElementById("current")[:textContent] = state.fetch("title")
          document.getElementById("body")[:innerHTML] = state.fetch("html")
          document.getElementById("body")[:className] = ""
          document.getElementById("notes")[:innerHTML] = state.fetch("notes_html")
          document.getElementById("page-footnote")[:textContent] = state.fetch("page_footnote")
          @renderer.resolve_links(document.getElementById("body"))
          @renderer.prepare_image_columns(document.getElementById("body"))
          @renderer.resolve_links(document.getElementById("notes"))
        end
        sync_speaker
        update_speaker_elapsed
      end

      def update_speaker_elapsed
        return unless @speaker && @speaker[:closed] == JS::False
        output = @speaker[:document].getElementById("elapsed")
        return if output == JS::Null
        seconds = @started_at ? ((JS.global[:Date].now.to_f - @started_at) / 1000).floor : nil
        output[:textContent] = seconds ? format("%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : "--:--:--"
      end

      def sync_speaker
        return unless @speaker && @speaker[:closed] == JS::False
        slide = @presentation.slides[@index]
        @speaker.postMessage(JSON.generate({ position: "#{@index + 1} / #{@sections.length}", title: slide.title, html: slide.html, notes_html: slide.notes_html, page_footnote: slide.page_footnote }), JS.global[:location][:origin])
      end

      def prepare_pages(notes)
        pages = element("print-pages")
        pages.replaceChildren
        @presentation.slides.each_with_index do |slide, index|
          [false, *(notes ? [true] : [])].each do |is_note|
            section = is_note ? @renderer.slide(slide, notes: true) : @sections[index].cloneNode(true)
            section.querySelectorAll(".youtube-overlay").to_a.each(&:remove)
            if is_note
              element("stage").appendChild(section)
              @layout.wait_assets(section)
              @layout.fit_slide(section, slide.number)
            end
            sheet = @document.createElement("div")
            sheet[:className] = "print-sheet"
            sheet.appendChild(section)
            pages.appendChild(sheet)
          end
        end
        @layout.wait_assets(pages)
        pages.setAttribute("aria-hidden", "false")
        element("status")[:textContent] = "印刷準備完了 (#{pages[:childElementCount].to_i} ページ)"
      end

      def print_pages(notes)
        prepare_pages(notes)
        JS.global.print
      end
    end
  end
end
