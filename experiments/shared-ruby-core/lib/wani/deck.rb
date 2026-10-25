require "kramdown"

module Wani
  # Shared by native CRuby and ruby.wasm without platform-specific branches.
  class Deck
    def initialize(markdown)
      sources = markdown.split(/^[ \t]*---[ \t]*\r?$/, -1)
      sources = [""] if sources.empty?
      @slides = sources.map do |source|
        Kramdown::Document.new(source, input: "Kramdown", syntax_highlighter: nil).to_html
      end
      @index = 0
    end

    def move(delta)
      @index = (@index + delta).clamp(0, @slides.length - 1)
      self
    end

    def snapshot
      {
        "html" => @slides.fetch(@index),
        "index" => @index,
        "total" => @slides.length,
        "previous_disabled" => @index.zero?,
        "next_disabled" => @index == @slides.length - 1
      }
    end
  end
end
