module Wani
  module Core
    Diagnostic = Struct.new(:severity, :message, :slide, keyword_init: true) do
      def to_h
        { severity: severity.to_s, message: message, slide: slide }
      end
    end
    Slide = Struct.new(:number, :title, :html, :notes_html, :images, keyword_init: true)
    Presentation = Struct.new(:slides, :footer, :decorations, :diagnostics, keyword_init: true) do
      def to_h
        { slides: slides.map(&:to_h), footer: footer, decorations: decorations, diagnostics: diagnostics.map(&:to_h) }
      end
    end
  end
end
