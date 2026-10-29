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
        response = JS.global.fetch("/talk/slides.md").await
        raise "Markdown を読み込めません (HTTP #{response[:status].to_i})" unless response[:ok] == JS::True
        @presentation = Core::Parser.new.parse(response.text.await.to_s)
        @presentation.diagnostics.each { |item| warn("#{item.slide ? "スライド #{item.slide}: " : ""}#{item.message}") }
        @renderer = Renderer.new(@document, @presentation)
        @sections = @presentation.slides.map { |slide| @renderer.slide(slide) }
        @sections.each { |section| element("stage").appendChild(section) }
        font_sections = @sections + @presentation.slides.map { |slide| @renderer.slide(slide, notes: true) }
        Fonts.new(@document) { |message| warn(message) }.apply(@presentation.fonts, font_sections)
        @layout.wait_assets(element("stage"))
        @sections.each_with_index { |section, index| @layout.fit_slide(section, index + 1) }
        prepare_pages(false)
        prepare_timer_image
        bind_events
        @waiting_to_start = JS.global[:location][:hash].to_s.empty?
        go(hash_index)
        %w[previous next fullscreen speaker print print-notes].each { |id| element(id)[:disabled] = false }
        update_buttons
        if @waiting_to_start
          element("start-overlay")[:hidden] = false
          element("viewport")[:inert] = true
          element("start-presentation").focus
        else
          start_timer
        end
        element("status")[:textContent] = "準備できました"
      end

      private

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
          start_timer
        end
        element("previous").addEventListener("click") { go(@index - 1) }
        element("next").addEventListener("click") { go(@index + 1) }
        element("fullscreen").addEventListener("click") { fullscreen }
        element("speaker").addEventListener("click") { speaker }
        element("print").addEventListener("click") { async { print_pages(false) } }
        element("print-notes").addEventListener("click") { async { print_pages(true) } }
        @document.addEventListener("keydown") do |event|
          target = event[:target]
          next if event[:ctrlKey] == JS::True || event[:altKey] == JS::True || event[:metaKey] == JS::True
          next if %w[INPUT TEXTAREA SELECT].include?(target[:tagName].to_s) || target[:isContentEditable] == JS::True
          next if @waiting_to_start && !%w[f F Escape n N].include?(event[:key].to_s)
          handled = true
          case event[:key].to_s
          when "ArrowRight", " ", "PageDown" then go(@index + 1)
          when "ArrowLeft", "PageUp" then go(@index - 1)
          when "Home" then go(0)
          when "End" then go(@sections.length - 1)
          when "f", "F" then fullscreen
          when "Escape" then exit_fullscreen
          when "n", "N" then speaker
          else handled = false
          end
          event.preventDefault if handled
        end
        JS.global.addEventListener("resize") { @layout.scale }
        JS.global.addEventListener("hashchange") { go(hash_index) }
        @document.addEventListener("fullscreenchange") { @layout.scale }
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
        @speaker.addEventListener("load") do |_event|
          @speaker.addEventListener("message") do |event|
            next unless event[:origin].to_s == JS.global[:location][:origin].to_s && event[:source] == JS.global
            state = JSON.parse(event[:data].to_s)
            document = @speaker[:document]
            document.getElementById("position")[:textContent] = state.fetch("position")
            document.getElementById("current")[:textContent] = state.fetch("title")
            document.getElementById("body")[:innerHTML] = state.fetch("html")
            document.getElementById("notes")[:innerHTML] = state.fetch("notes_html")
            document.getElementById("page-footnote")[:textContent] = state.fetch("page_footnote")
            @renderer.resolve_links(document.getElementById("body"))
            @renderer.resolve_links(document.getElementById("notes"))
          end
          sync_speaker
        end
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
