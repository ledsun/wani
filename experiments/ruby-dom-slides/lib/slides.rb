require "js"
require_relative "markdown"

module Wani
  class Slides
    def initialize
      @document = JS.global[:document]
      @source = element("markdown")
      @deck = element("slides")
      @previous = element("previous")
      @next = element("next")
      @position = element("position")
      @sections = []
      @index = 0
    end

    def start
      element("render").addEventListener("click") { render }
      @previous.addEventListener("click") { move(-1) }
      @next.addEventListener("click") { move(1) }
      @document.addEventListener("keydown") { |event| on_key(event) }
      render
      element("render")[:disabled] = false
      element("status")[:textContent] = "Ruby の DOM 操作の準備ができました"
    end

    private

    def element(id)
      @document.getElementById(id)
    end

    def render
      # Separator is a line containing only --- (surrounding whitespace allowed).
      sources = @source[:value].to_s.split(/^[ \t]*---[ \t]*\r?$/, -1)
      sources = [""] if sources.empty?
      @deck.replaceChildren
      @sections = sources.map do |source|
        section = @document.createElement("section")
        section[:className] = "slide"
        section.setAttribute("aria-label", "スライド #{@deck[:childElementCount].to_i + 1}")
        # This experiment accepts trusted Markdown, including raw HTML.
        section[:innerHTML] = Wani::Markdown.render(source)
        @deck.appendChild(section)
        section
      end
      @index = 0
      update
    end

    def on_key(event)
      return if event[:ctrlKey] == JS::True || event[:altKey] == JS::True || event[:metaKey] == JS::True
      target = event[:target]
      return if %w[INPUT TEXTAREA SELECT].include?(target[:tagName].to_s)
      return if target[:isContentEditable] == JS::True

      case event[:key].to_s
      when "ArrowRight"
        event.preventDefault
        move(1)
      when "ArrowLeft"
        event.preventDefault
        move(-1)
      end
    end

    def move(delta)
      @index = (@index + delta).clamp(0, @sections.length - 1)
      update
    end

    def update
      @sections.each_with_index { |section, index| section[:hidden] = index != @index }
      @previous[:disabled] = @index.zero?
      @next[:disabled] = @index == @sections.length - 1
      @position[:textContent] = "#{@index + 1} / #{@sections.length}"
    end
  end
end

Wani::Slides.new.start
