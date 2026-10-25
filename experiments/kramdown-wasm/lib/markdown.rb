$LOAD_PATH.unshift("/app/bundle/kramdown/lib", "/app/bundle/rexml/lib")
require "kramdown"

module Wani
  module Markdown
    def self.render(source)
      Kramdown::Document.new(source, input: "Kramdown", syntax_highlighter: nil).to_html
    end
  end
end
