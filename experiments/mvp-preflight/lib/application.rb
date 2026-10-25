$LOAD_PATH.unshift("/app/bundle/kramdown/lib", "/app/bundle/rexml/lib", "/app/bundle/kramdown-parser-gfm/lib")
require "js"
require "json"
require_relative "parser"

module Preflight
  class Application
    def start
      $app = self
      @document = JS.global[:document]
      @index = 0
      @warnings = []
      params = JS.global[:URLSearchParams].new(JS.global[:location][:search])
      file = params.get("file").to_s
      file = "slides.md" if file == "null"
      response = JS.global.fetch(file).await
      raise "Markdown HTTP #{response[:status].to_i}" unless response[:ok] == JS::True
      @model = Parser.new.parse(response.text.await.to_s)
      element("model")[:textContent] = JSON.generate(@model)
      @sections = @model.fetch("slides").each_with_index.map do |slide, index|
        make_slide(@document, slide, index)
      end
      @sections.each { |section| element("stage").appendChild(section) }
      JS.global[:document][:fonts][:ready].await
      wait_images(element("stage"))
      @sections.each_with_index { |section, index| fit_slide(section, index) }
      element("previous").addEventListener("click") { move(-1) }
      element("next").addEventListener("click") { move(1) }
      element("fullscreen").addEventListener("click") { fullscreen }
      element("exit-fullscreen").addEventListener("click") { exit_fullscreen }
      element("speaker").addEventListener("click") { open_speaker }
      element("print").addEventListener("click") { run_async { print_pages(false) } }
      element("print-notes").addEventListener("click") { run_async { print_pages(true) } }
      @document.addEventListener("keydown") do |event|
        case event[:key].to_s
        when "ArrowRight" then event.preventDefault; move(1)
        when "ArrowLeft" then event.preventDefault; move(-1)
        when "f", "F" then fullscreen
        when "n", "N" then open_speaker
        when "Escape" then exit_fullscreen
        end
      end
      JS.global.addEventListener("resize") { scale }
      update
      element("status")[:textContent] = "ready"
    end

    def print_pages(notes)
      pages = element("print-pages")
      pages.replaceChildren
      @sections.each_with_index do |section, index|
        sheet = @document.createElement("div")
        sheet[:className] = "print-sheet"
        sheet.appendChild(section.cloneNode(true))
        pages.appendChild(sheet)
        if notes
          slide = { "title" => "Notes #{index + 1}", "html" => @model['slides'][index]['notes_html'] }
          note_sheet = @document.createElement("div")
          note_sheet[:className] = "print-sheet"
          note_slide = make_slide(@document, slide, index)
          # Measure at screen size before the print tree is hidden again.
          element("stage").appendChild(note_slide)
          fit_slide(note_slide, index)
          note_sheet.appendChild(note_slide)
          pages.appendChild(note_sheet)
        end
      end
      @document[:fonts][:ready].await
      wait_images(pages)
      element("status")[:textContent] = "print-ready:#{pages[:childElementCount].to_i}"
      JS.global.print
    end

    private

    def element(id)
      @document.getElementById(id)
    end

    def run_async(&block)
      # A callback starts on the VM's root fiber. Await needs its own fiber;
      # calling vm.evalAsync from inside Ruby would re-enter the same VM.
      Fiber.new do
        block.call
      rescue => error
        element("status")[:textContent] = "ERROR: #{error.class}: #{error.message}"
      end.transfer
    end

    def make_slide(document, slide, index)
      section = document.createElement("section")
      section[:className] = "slide"
      section.setAttribute("data-slide", (index + 1).to_s)
      title = document.createElement("h1")
      title[:className] = "title"
      title[:textContent] = slide.fetch("title")
      title[:style][:display] = "none" if slide.fetch("title").empty?
      section.appendChild(title)
      body = document.createElement("div")
      body[:className] = "body"
      body[:innerHTML] = slide.fetch("html")
      section.appendChild(body)
      footer = document.createElement("footer")
      footer[:className] = "footer"
      footer[:textContent] = "#{@model.fetch('footer')}  🐇 🦈"
      section.appendChild(footer)
      section
    end

    def wait_images(root)
      root.querySelectorAll("img").to_a.each do |image|
        unless image[:complete] == JS::True
          JS.global[:Promise].new do |resolve, _reject|
            image.addEventListener("load", ->(_event) { resolve.apply(true); nil }, { once: true }.to_js)
            image.addEventListener("error", ->(_event) { resolve.apply(false); nil }, { once: true }.to_js)
          end.await
        end
        @warnings << "image failed: #{image.getAttribute('src')}" if image[:naturalWidth].to_i.zero?
      end
    end

    def fit_slide(section, index)
      section[:style][:display] = "flex"
      fit(section.querySelector(".title"), 24, 180) unless section.querySelector(".title")[:style][:display].to_s == "none"
      body = section.querySelector(".body")
      fit(body, 16, 160)
      @warnings << "slide #{index + 1}: overflow: #{body[:textContent].to_s[0, 100]}" unless fits?(body)
      section[:style][:display] = ""
      element("warnings")[:textContent] = @warnings.join("\n")
    end

    def fits?(node)
      node[:scrollWidth].to_i <= node[:clientWidth].to_i && node[:scrollHeight].to_i <= node[:clientHeight].to_i
    end

    def fit(node, minimum, maximum)
      low = minimum
      high = maximum
      best = minimum
      while low <= high
        middle = (low + high) / 2
        node[:style][:fontSize] = "#{middle}px"
        if fits?(node)
          best = middle
          low = middle + 1
        else
          high = middle - 1
        end
      end
      node[:style][:fontSize] = "#{best}px"
    end

    def scale
      viewport = element("viewport")
      ratio = [viewport[:clientWidth].to_f / 1920, viewport[:clientHeight].to_f / 1080].min
      element("stage")[:style][:transform] = "scale(#{ratio})"
    end

    def move(delta)
      @index = (@index + delta).clamp(0, @sections.length - 1)
      update
    end

    def update
      @sections.each_with_index { |section, index| section[:classList].toggle("active", index == @index) }
      element("position")[:textContent] = "#{@index + 1} / #{@sections.length}"
      JS.global[:location][:hash] = "slide=#{@index + 1}"
      scale
      sync_speaker
    end

    def fullscreen
      # Call immediately inside the user callback, before any await.
      @document[:documentElement].requestFullscreen.then(
        ->(_value) { element("status")[:textContent] = "fullscreen"; nil },
        ->(error) { element("status")[:textContent] = "fullscreen rejected: #{error[:name]}"; nil }
      )
    end

    def exit_fullscreen
      return if @document[:fullscreenElement] == JS::Null
      @document.exitFullscreen.then(->(_value) { element("status")[:textContent] = "ready"; nil })
    end

    def open_speaker
      @speaker = JS.global.open("speaker.html", "wani-speaker")
      if @speaker == JS::Null
        element("status")[:textContent] = "popup blocked"
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
        end
        sync_speaker
      end
    end

    def sync_speaker
      return unless @speaker && @speaker[:closed] == JS::False
      slide = @model.fetch("slides")[@index]
      @speaker.postMessage(JSON.generate({ "position" => "#{@index + 1}", "title" => slide.fetch("title"), "html" => slide.fetch("html"), "notes_html" => slide.fetch("notes_html") }), JS.global[:location][:origin])
    end
  end
end
