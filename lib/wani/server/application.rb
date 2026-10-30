require "uri"
require "json"
require_relative "../fonts/manager"
require_relative "../../wani"

module Wani
  module Server
    # Only the selected Markdown, images below its directory and fixed gem assets are public.
    class Application
      ASSETS = %w[index.html style.css highlight.css rouge.LICENSE bootstrap.rb speaker.html rabbit.svg shark.svg time-expired.webp runtime.pr672.js wani.wasm runtime.LICENSE runtime.NOTICE build.json
                  fonts/IBMPlexSansJP-Regular.woff2 fonts/IBMPlexSansJP-Bold.woff2
                  fonts/UDEVGothic-Regular.ttf fonts/UDEVGothic-Bold.ttf].freeze
      TYPES = { ".html" => "text/html; charset=utf-8", ".css" => "text/css; charset=utf-8", ".rb" => "text/plain; charset=utf-8", ".js" => "text/javascript", ".wasm" => "application/wasm", ".md" => "text/plain; charset=utf-8", ".svg" => "image/svg+xml", ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp", ".json" => "application/json", ".woff2" => "font/woff2", ".ttf" => "font/ttf" }.freeze
      IMAGES = %w[.png .jpg .jpeg .webp .svg].freeze

      def initialize(file, assets: File.join(Wani::ROOT, "assets"), diagnostics: nil)
        @file = File.realpath(file)
        raise ArgumentError, "Markdown is not a file: #{file}" unless File.file?(@file)
        @root = File.dirname(@file)
        @assets = File.realpath(assets)
        @diagnostics = diagnostics
        report_font(File.read(@file, encoding: "UTF-8")) if @diagnostics
      end

      def call(raw_path)
        path = decode(raw_path)
        if path == "/talk/fonts.json"
          return [200, { "Content-Type" => "application/json", "Cache-Control" => "no-store" }, JSON.generate(Fonts::Manager.new(@root).list)]
        end
        file = if path == "/"
                 File.join(@assets, "index.html")
               elsif path == "/talk/slides.md"
                 @file
               elsif path.start_with?("/assets/") && ASSETS.include?(path.delete_prefix("/assets/"))
                 contained(@assets, path.delete_prefix("/assets/"))
               elsif path.start_with?("/talk/fonts/") && Fonts::Manager.new(@root).list.values.any? { |entry| entry.fetch("files").include?(path.delete_prefix("/talk/")) }
                 contained(@root, path.delete_prefix("/talk/"))
               elsif path.start_with?("/talk/") && IMAGES.include?(File.extname(path).downcase)
                 contained(@root, path.delete_prefix("/talk/"))
               else
                 return [404, {}, "Not found"]
               end
        return [404, {}, "Not found"] unless File.file?(file)
        type = TYPES.fetch(File.extname(file).downcase, "text/plain; charset=utf-8")
        headers = { "Content-Type" => type, "X-Content-Type-Options" => "nosniff", "Cache-Control" => "no-store" }
        if type.start_with?("image/")
          headers["Content-Security-Policy"] = "sandbox; default-src 'none'; style-src 'unsafe-inline'"
        else
          headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' https: http:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
        end
        body = File.binread(file)
        report_font(body.dup.force_encoding(Encoding::UTF_8)) if path == "/talk/slides.md" && @diagnostics
        [200, headers, body]
      rescue ArgumentError, EncodingError
        [403, {}, "Forbidden"]
      rescue Errno::ENOENT, Errno::ENOTDIR
        [404, {}, "Not found"]
      rescue Errno::EACCES
        [403, {}, "Forbidden"]
      end

      private

      def report_font(source)
        message = begin
          name = Core::Parser.new.parse(source).fonts["default"]
          if name && !Core::Fonts.resolve(Fonts::Manager.new(@root).list, name)
            "warning: Unregistered font: #{name}; using fallback"
          end
        rescue Core::Parser::Error, ArgumentError => error
          "error: #{error.message}"
        end
        @diagnostics.call(message) if message && message != @last_diagnostic
        @last_diagnostic = message
      end

      def decode(raw)
        raw = raw.split("?", 2).first
        raise ArgumentError if raw.match?(/%(?![0-9a-fA-F]{2})/)
        path = URI::RFC2396_PARSER.unescape(raw).force_encoding(Encoding::UTF_8)
        raise ArgumentError unless path.valid_encoding? && path.start_with?("/")
        raise ArgumentError if path.match?(/[\x00-\x1f\x7f\\%]/) || path.split("/").any? { |part| part == ".." || part == "." }
        path
      end

      def contained(root, relative)
        resolved = File.realpath(File.join(root, relative))
        raise ArgumentError unless resolved.start_with?(root + File::SEPARATOR)
        resolved
      end
    end
  end
end
