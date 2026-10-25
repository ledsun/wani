require "uri"
require_relative "../../wani"

module Wani
  module Server
    # Only the selected Markdown, images below its directory and fixed gem assets are public.
    class Application
      ASSETS = %w[index.html style.css bootstrap.rb speaker.html rabbit.svg shark.svg runtime.pr672.js wani.wasm runtime.LICENSE runtime.NOTICE build.json].freeze
      TYPES = { ".html" => "text/html; charset=utf-8", ".css" => "text/css; charset=utf-8", ".rb" => "text/plain; charset=utf-8", ".js" => "text/javascript", ".wasm" => "application/wasm", ".md" => "text/plain; charset=utf-8", ".svg" => "image/svg+xml", ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp", ".json" => "application/json" }.freeze
      IMAGES = %w[.png .jpg .jpeg .webp .svg].freeze

      def initialize(file, assets: File.join(Wani::ROOT, "assets"))
        @file = File.realpath(file)
        raise ArgumentError, "Markdown is not a file: #{file}" unless File.file?(@file)
        @root = File.dirname(@file)
        @assets = File.realpath(assets)
      end

      def call(raw_path)
        path = decode(raw_path)
        file = if path == "/"
                 File.join(@assets, "index.html")
               elsif path == "/talk/slides.md"
                 @file
               elsif path.start_with?("/assets/") && ASSETS.include?(path.delete_prefix("/assets/"))
                 contained(@assets, path.delete_prefix("/assets/"))
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
        [200, headers, File.binread(file)]
      rescue ArgumentError, EncodingError
        [403, {}, "Forbidden"]
      rescue Errno::ENOENT, Errno::ENOTDIR
        [404, {}, "Not found"]
      rescue Errno::EACCES
        [403, {}, "Forbidden"]
      end

      private

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
