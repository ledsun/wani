module Wani
  module Browser
    class Renderer
      def initialize(document, presentation)
        @document, @presentation = document, presentation
      end

      def slide(slide, notes: false)
        section = @document.createElement("section")
        section[:className] = "slide"
        section.setAttribute("aria-label", "スライド #{slide.number}")
        title = child(section, "h1", "title")
        title[:textContent] = notes ? "ノート #{slide.number}" : slide.title
        title[:style][:display] = "none" if title[:textContent].to_s.empty?
        body = child(section, "div", "body")
        body[:innerHTML] = notes ? slide.notes_html : slide.html
        resolve_links(body)
        footer = child(section, "footer", "slide-footer")
        child(footer, "span", "footer-text")[:textContent] = @presentation.footer
        if @presentation.decorations
          decorations = child(footer, "span", "decorations")
          %w[rabbit shark].each do |name|
            image = child(decorations, "img", "decoration")
            image[:src] = "/assets/#{name}.svg"
            image[:alt] = ""
          end
        end
        section
      end

      def resolve_links(root)
        root.querySelectorAll("img, a").to_a.each do |node|
          attribute = node[:tagName].to_s == "IMG" ? "src" : "href"
          value = node.getAttribute(attribute).to_s
          node.setAttribute(attribute, JS.global[:URL].new(value, "#{JS.global[:location][:origin]}/talk/")[:href])
        end
      end

      private

      def child(parent, tag, class_name)
        element = @document.createElement(tag)
        element[:className] = class_name
        parent.appendChild(element)
        element
      end
    end
  end
end
