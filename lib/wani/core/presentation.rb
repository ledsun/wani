module Wani
  module Core
    Diagnostic = Struct.new(:severity, :message, :slide, keyword_init: true) do
      def to_h
        { severity: severity.to_s, message: message, slide: slide }
      end
    end
    Slide = Struct.new(:number, :title, :html, :notes_html, :images, :page_footnote, keyword_init: true)
    Presentation = Struct.new(:slides, :time_limit, :diagnostics, :fonts, keyword_init: true) do
      def to_h
        { slides: slides.map(&:to_h), time_limit: time_limit, diagnostics: diagnostics.map(&:to_h) }.tap { |data| data[:fonts] = fonts unless fonts.nil? || fonts.empty? }
      end
    end
  end
end
