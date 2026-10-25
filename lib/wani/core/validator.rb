require "uri"
require_relative "presentation"
module Wani
  module Core
    class Validator
      EXTENSIONS = %w[.png .jpg .jpeg .webp .svg].freeze
      def validate(presentation, base_dir:)
        diagnostics = presentation.diagnostics.dup
        presentation.slides.each do |slide|
          slide.images.each do |url|
            next if url.match?(/\Ahttps?:/i)
            path = url.split(/[?#]/, 2).first
            decoded = URI::RFC2396_PARSER.unescape(path)
            file = File.expand_path(decoded, base_dir)
            message = if !EXTENSIONS.include?(File.extname(path).downcase)
                        "Unsupported image type: #{url}"
                      elsif !File.file?(file)
                        "Missing image: #{url}"
                      elsif !File.realpath(file).start_with?(File.realpath(base_dir) + File::SEPARATOR)
                        "Image is outside the public Markdown directory: #{url}"
                      end
            diagnostics << Diagnostic.new(severity: :error, message: message, slide: slide.number) if message
          rescue ArgumentError, SystemCallError
            diagnostics << Diagnostic.new(severity: :error, message: "Invalid image path: #{url}", slide: slide.number)
          end
        end
        diagnostics
      end
    end
  end
end
