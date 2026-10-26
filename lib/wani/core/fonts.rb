require "yaml"

module Wani
  module Core
    module Fonts
      ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      module_function

      def settings(value)
        return {} if value.nil?
        raise ArgumentError, "font must be a non-empty font name or ID" unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\x00-\x1f]/)
        { "default" => value.strip }
      end

      def registry(source)
        data = YAML.safe_load(source, aliases: false) || {}
        raise ArgumentError, "Invalid font registry" unless data.is_a?(Hash)
        fonts = data.fetch("fonts", {})
        raise ArgumentError, "Invalid font registry" unless fonts.is_a?(Hash)
        fonts.each do |id, entry|
          raise ArgumentError, "Invalid font registration" unless id.is_a?(String) && ID.match?(id) && entry.is_a?(Hash)
          %w[family css_family version].each do |key|
            raise ArgumentError, "Invalid font #{key}" unless entry[key].is_a?(String) && !entry[key].empty?
          end
          raise ArgumentError, "Invalid managed files" unless entry["files"].is_a?(Array) && entry["files"].all? { |path| path.is_a?(String) }
          paths = [entry["stylesheet"], entry["license"], *entry.fetch("files", [])]
          raise ArgumentError, "Invalid font files" unless paths.all? { |path| path.is_a?(String) && path.match?(%r{\Afonts/#{Regexp.escape(id)}/(?:font\.css|LICENSE|files/[a-zA-Z0-9_-]+\.woff2)\z}) }
          raise ArgumentError, "Missing managed font files" unless paths.first(2).all? { |path| entry.fetch("files", []).include?(path) }
        end
        fonts
      rescue Psych::Exception, NoMethodError, TypeError
        raise ArgumentError, "Invalid font registry"
      end

      def resolve(fonts, name)
        fonts[name] || fonts.values.find { |entry| entry["family"].casecmp?(name) }
      end
    end
  end
end
