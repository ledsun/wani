require "json"
require_relative "../core/fonts"

module Wani
  module Browser
    class Fonts
      def initialize(document, &warn)
        @document, @warn = document, warn
      end

      def apply(settings, sections)
        name = settings["default"]
        return unless name
        response = JS.global.fetch("/talk/fonts.json").await
        raise "フォント登録情報を読み込めません" unless response[:ok] == JS::True
        registry = JSON.parse(response.text.await.to_s)
        entry = Core::Fonts.resolve(registry, name)
        unless entry
          @warn.call("未登録のフォント: #{name}。代替フォントを使用します")
          return
        end
        link = @document.createElement("link")
        link[:rel] = "stylesheet"
        link[:href] = "/talk/#{entry.fetch('stylesheet')}"
        loaded = JS.global[:Promise].new do |resolve, _reject|
          link.addEventListener("load", ->(_) { resolve.apply(true); nil }, { once: true }.to_js)
          link.addEventListener("error", ->(_) { resolve.apply(false); nil }, { once: true }.to_js)
          JS.global.setTimeout(-> { resolve.apply(false); nil }, 20_000)
          @document[:head].appendChild(link)
        end.await
        raise "CSSを読み込めません" unless loaded == JS::True
        family = JSON.generate(entry.fetch("css_family"))
        # All slide and note characters are supplied, including characters in hidden slides.
        text = sections.map { |section| section[:textContent].to_s }.join
        entry.fetch("styles", ["normal"]).each do |style|
          [400, 700].each do |weight|
            loading = @document[:fonts].load("#{style} #{weight} 16px #{family}", text)
            timeout = JS.global[:Promise].new do |resolve, _reject|
              JS.global.setTimeout(-> { resolve.apply(false); nil }, 20_000)
            end
            faces = JS.global[:Promise].race([loading, timeout].to_js).await
            raise "フォント読み込みがタイムアウトしました" if faces == JS::False
            raise "対応するフォントがありません" if faces[:length].to_i.zero? && !text.empty?
          end
        end
        @document[:fonts][:ready].await
        style = @document.createElement("style")
        style[:textContent] = %(.slide .title, .slide .body { font-family: #{family}, "IBM Plex Sans JP", sans-serif; })
        @document[:head].appendChild(style)
      rescue => error
        link.remove if link
        @warn.call("フォントを読み込めませんでした: #{name} (#{error.message})。代替フォントを使用します")
      end
    end
  end
end
