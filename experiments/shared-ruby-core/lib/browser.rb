# Only the browser adapter knows the guest filesystem layout and DOM API.
$LOAD_PATH.unshift("/app/bundle/kramdown/lib", "/app/bundle/rexml/lib")
require "js"
require_relative "wani/deck"

module Wani
  class Browser
    def initialize
      @document = JS.global[:document]
    end

    def start
      element("render").addEventListener("click") { render }
      element("previous").addEventListener("click") { move(-1) }
      element("next").addEventListener("click") { move(1) }
      @document.addEventListener("keydown") { |event| on_key(event) }
      render
      element("render")[:disabled] = false
      element("status")[:textContent] = "共通 Ruby モジュールの準備ができました"
    end

    private

    def element(id)
      @document.getElementById(id)
    end

    def render
      @deck = Deck.new(element("markdown")[:value].to_s)
      update
    end

    def move(delta)
      @deck.move(delta)
      update
    end

    def update
      state = @deck.snapshot
      # Trusted Markdown only: raw HTML is accepted in this experiment.
      element("slides")[:innerHTML] = state.fetch("html")
      element("position")[:textContent] = "#{state.fetch('index') + 1} / #{state.fetch('total')}"
      element("previous")[:disabled] = state.fetch("previous_disabled")
      element("next")[:disabled] = state.fetch("next_disabled")
    end

    def on_key(event)
      return if event[:ctrlKey] == JS::True || event[:altKey] == JS::True || event[:metaKey] == JS::True
      target = event[:target]
      return if %w[INPUT TEXTAREA SELECT].include?(target[:tagName].to_s) || target[:isContentEditable] == JS::True

      delta = { "ArrowLeft" => -1, "ArrowRight" => 1 }[event[:key].to_s]
      return unless delta
      event.preventDefault
      move(delta)
    end
  end
end

Wani::Browser.new.start
