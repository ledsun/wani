require_relative "bridge_progress"

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
        if title[:textContent].to_s.empty?
          title[:style][:display] = "none"
          section[:className] = "slide titleless"
        end
        section[:classList].add("cover") if slide.number == 1 && !notes
        section[:classList].add("multiline-title") if slide.number == 1 && !notes && slide.title.include?("\n")
        body = child(section, "div", "body")
        body[:innerHTML] = notes ? slide.notes_html : slide.html
        resolve_links(body)
        prepare_image_columns(body) unless notes
        body.querySelectorAll("p").to_a.each do |paragraph|
          children = paragraph[:children].to_a
          next unless children.length == 1 && children.first[:classList].contains("youtube-video") == JS::True
          copy = paragraph.cloneNode(true)
          copy.querySelector(".youtube-video").remove
          paragraph[:classList].add("youtube-only") if copy[:textContent].to_s.strip.empty?
        end
        prepare_videos(body)
        footer = child(section, "footer", "slide-footer")
        child(footer, "span", "page-footnote")[:textContent] = slide.page_footnote
        number = child(footer, "span", "slide-number")
        number[:textContent] = "#{slide.number}/#{@presentation.slides.length}"
        number.setAttribute("aria-label", "#{@presentation.slides.length} ページ中 #{slide.number} ページ")
        progress = BridgeProgress.new(slide.number, @presentation.slides.length)
        decorations = child(footer, "span", "decorations")
        decorations.setAttribute("aria-hidden", "true")
        decorations.setAttribute("data-slide", slide.number.to_s)
        decorations.setAttribute("data-sharks", progress.sharks.to_s)
        decorations.setAttribute("data-rabbit", progress.rabbit_fraction.to_s)
        decorations[:style].setProperty("--rabbit-progress", progress.rabbit_fraction.to_s)
        decorations[:style].setProperty("--rabbit-from", progress.rabbit_fraction.to_s)
        child(decorations, "span", "island island-left")
        child(decorations, "span", "island island-right")
        bridge = child(decorations, "span", "bridge")
        BridgeProgress::SEGMENTS.times do |index|
          segment = child(bridge, "span", "bridge-segment")
          segment.setAttribute("data-present", (index >= BridgeProgress::SEGMENTS - progress.sharks).to_s)
          image = child(segment, "img", "bridge-wani")
          image[:src] = "/assets/shark.svg"
          image[:alt] = ""
        end
        rabbit = child(child(decorations, "span", "rabbit-position"), "img", "rabbit-image")
        rabbit[:src] = "/assets/rabbit.svg"
        rabbit[:alt] = ""
        section
      end

      def transition(section, from_number)
        scene = section.querySelector(".decorations")
        return if scene == JS::Null
        previous = BridgeProgress.new(from_number, @presentation.slides.length)
        current = BridgeProgress.new(scene.getAttribute("data-slide").to_s.to_i, @presentation.slides.length)
        scene[:style].setProperty("--rabbit-from", previous.rabbit_fraction.to_s)
        scene.setAttribute("data-moving", (previous.rabbit_fraction != current.rabbit_fraction).to_s)
        scene.setAttribute("data-direction", current.rabbit_fraction < previous.rabbit_fraction ? "left" : "right")
        scene.querySelectorAll(".bridge-segment").to_a.each_with_index do |segment, index|
          appearing = index >= BridgeProgress::SEGMENTS - current.sharks && index < BridgeProgress::SEGMENTS - previous.sharks
          segment.setAttribute("data-appearing", appearing.to_s)
        end
      end

      def prepare_videos(root)
        root.querySelectorAll(".youtube-video").to_a.each do |video|
          button = video.querySelector(".youtube-play")
          button.addEventListener("click") do
            section = video.closest(".slide")
            next unless section.querySelector(".youtube-overlay") == JS::Null
            overlay = child(section, "div", "youtube-overlay")
            frame = child(overlay, "iframe", "youtube-frame")
            url = video.getAttribute("data-youtube-src").to_s
            frame[:src] = "#{url}#{url.include?("?") ? "&" : "?"}autoplay=1"
            frame[:title] = button.getAttribute("aria-label")
            frame.setAttribute("allow", "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share")
            frame.setAttribute("allowfullscreen", "")
            close = child(overlay, "button", "youtube-close")
            close[:type] = "button"
            close[:textContent] = "閉じる ×"
            close.setAttribute("aria-label", "動画を閉じる")
            close.addEventListener("click") do
              overlay.remove
              button.focus
            end
            close.focus
          end
        end
      end

      def resolve_links(root)
        root.querySelectorAll("img, a").to_a.each do |node|
          attribute = node[:tagName].to_s == "IMG" ? "src" : "href"
          value = node.getAttribute(attribute).to_s
          node.setAttribute(attribute, JS.global[:URL].new(value, "#{JS.global[:location][:origin]}/talk/")[:href])
        end
      end

      def prepare_image_columns(body)
        image = body[:children].to_a.find do |element|
          element[:tagName].to_s == "P" && element[:children][:length].to_i == 1 &&
            element.querySelector("img.wani-image-left, img.wani-image-right") != JS::Null && element[:textContent].to_s.strip.empty?
        end
        return unless image
        side = image.querySelector("img")[:className].to_s.end_with?("left") ? "left" : "right"
        text = body[:ownerDocument].createElement("div")
        text[:className] = "image-column-text"
        body[:childNodes].to_a.each { |node| text.appendChild(node) unless node == image }
        image[:classList].add("image-column-image")
        body[:classList].add("image-columns", "image-#{side}")
        body.appendChild(side == "left" ? image : text)
        body.appendChild(side == "left" ? text : image)
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
