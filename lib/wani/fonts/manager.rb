require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "tempfile"
require_relative "http"
require_relative "../core/fonts"
require_relative "../core/parser"

module Wani
  module Fonts
    class Manager
      def initialize(root = Dir.pwd, http: HTTP.new)
        @root, @http = File.realpath(root), http
      end

      def list
        path = safe_path(".wani/fonts.yml")
        File.exist?(path) ? Core::Fonts.registry(File.read(path)) : {}
      end

      def add(source)
        locked do
          @bytes = 0
          id = identify(source)
          fonts = list
          raise Error, "Font already installed: #{id}" if fonts.key?(id)
          meta = json("https://api.fontsource.org/v1/fonts/#{id}")
          raise Error, "Font metadata mismatch" unless meta.is_a?(Hash) && meta["id"] == id && meta["family"].is_a?(String)
          raise Error, "Font already installed: #{meta['family']}" if Core::Fonts.resolve(fonts, meta['family'])
          raise Error, "Invalid font styles" unless meta["styles"].is_a?(Array) && !meta["styles"].empty? && (meta["styles"] - %w[normal italic]).empty?
          raise Error, "Invalid font weights" unless meta["weights"].is_a?(Array) && meta["weights"].all? { |weight| weight.is_a?(Numeric) }
          versions = json("https://api.fontsource.org/v1/version/#{id}")
          variable = meta["variable"] == true && versions["latestVariable"].is_a?(String)
          version = versions.fetch(variable ? "latestVariable" : "latest")
          raise Error, "Invalid package version" unless version.is_a?(String) && version.match?(/\A\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\z/)
          package = "@fontsource#{variable ? '-variable' : ''}/#{id}"
          base = "https://cdn.jsdelivr.net/npm/#{package}@#{version}/"
          manifest = json(base + "package.json")
          raise Error, "Package/version mismatch" unless manifest["name"] == package && manifest["version"] == version
          raise Error, "Package has no license information" unless manifest["license"].is_a?(String) && !manifest["license"].empty?
          weights = [400, 700] & meta.fetch("weights").map(&:to_i)
          raise Error, "Font has neither weight 400 nor 700" if weights.empty?
          css_names = variable ? meta.fetch("styles").map { |style| style == "normal" ? "index.css" : "wght-#{style}.css" } : weights.product(meta.fetch("styles")).map { |weight, style| "#{weight}#{style == 'normal' ? '' : "-#{style}"}.css" }
          css = css_names.map { |name| download(base + name).force_encoding("UTF-8") }.join("\n")
          raise Error, "Invalid font CSS" unless css.valid_encoding? && !css.match?(/@import/i)
          # Retain all faces and unicode ranges, dropping only the WOFF fallback source.
          css = css.gsub(/src\s*:\s*([^;]+);/i) do
            sources = Regexp.last_match(1).scan(/url\(\s*['"]?(\.\/files\/[a-zA-Z0-9_-]+\.woff2)['"]?\s*\)\s*format\(['"]woff2(?:-variations)?['"]\)/).flatten
            raise Error, "CSS face has no supported WOFF2 source" if sources.empty?
            "src: url('#{sources.first}') format('woff2');"
          end
          urls = css.scan(/url\(([^)]+)\)/i).flatten.map { |url| url.strip.delete_prefix("'").delete_suffix("'") }
          raise Error, "Invalid CSS font URLs" if urls.empty? || urls.any? { |url| !url.match?(%r{\A\./files/[a-zA-Z0-9_-]+\.woff2\z}) }
          families = css.scan(/font-family:\s*['"]([^'"]+)['"]\s*;/).flatten.uniq
          raise Error, "Unexpected CSS font family" unless families.length == 1 && [meta['family'], "#{meta['family']} Variable"].include?(families.first)
          destination = safe_path("fonts/#{id}")
          raise Error, "Destination already exists: fonts/#{id}" if File.exist?(destination)
          FileUtils.mkdir_p(safe_path("fonts"))
          Dir.mktmpdir(".wani-font-", @root) do |temporary|
            stage = File.join(temporary, "font")
            FileUtils.mkdir_p("#{stage}/files")
            File.write("#{stage}/font.css", css)
            urls.uniq.each do |url|
              data = download(base + url.delete_prefix("./"))
              raise Error, "Invalid or incomplete WOFF2: #{url}" unless data.bytesize >= 48 && data.start_with?("wOF2") && data.byteslice(8, 4).unpack1("N") == data.bytesize
              File.binwrite(File.join(stage, url), data)
            end
            license = download(base + "LICENSE").force_encoding("UTF-8")
            raise Error, "Invalid license document" unless license.valid_encoding? && license.length >= 100 && !license.match?(/<\s*(?:!doctype|html)/i)
            File.write("#{stage}/LICENSE", license)
            files = Dir.glob("#{stage}/**/*").select { |path| File.file?(path) }.to_h { |path| ["fonts/#{id}/#{path.delete_prefix(stage + '/')}", Digest::SHA256.file(path).hexdigest] }
            entry = { "family" => meta["family"], "css_family" => families.first, "source" => "fontsource", "fontsource_id" => id, "version" => version, "package" => package, "stylesheet" => "fonts/#{id}/font.css", "license" => "fonts/#{id}/LICENSE", "license_type" => manifest["license"], "variable" => variable, "weights" => weights, "styles" => meta["styles"], "subsets" => meta["subsets"], "files" => files.keys, "sha256" => files }
            File.rename(stage, destination)
            begin
              save(fonts.merge(id => entry))
            rescue Exception
              FileUtils.remove_entry(destination)
              raise
            end
            entry
          end
        end
      rescue KeyError, JSON::ParserError => error
        raise Error, "Invalid Fontsource response: #{error.message}"
      end

      def remove(id, confirm: nil)
        raise Error, "Invalid font ID" unless Core::Fonts::ID.match?(id)
        locked do
          fonts = list
          entry = fonts.fetch(id) { raise Error, "Font not installed: #{id}" }
          used = Dir.glob(File.join(@root, "**/*.{md,markdown}")).select do |file|
            next false if File.symlink?(file) || !File.realpath(file).start_with?(@root + "/")
            name = Core::Parser.new.parse(File.read(file, encoding: "UTF-8")).fonts["default"]
            name && Core::Fonts.resolve(fonts, name) == entry
          rescue Core::Parser::Error
            true # A malformed document cannot establish that removal is safe.
          end
          raise Error, "Font is used by Markdown: #{used.join(', ')}; removal cancelled" if !used.empty? && !(confirm && confirm.call(used))
          paths = entry.fetch("files").map { |relative| [relative, safe_path(relative)] }
          paths.each do |relative, path|
            next unless File.exist?(path)
            raise Error, "Managed file was changed; refusing removal: #{relative}" unless entry.fetch("sha256", {})[relative] == Digest::SHA256.file(path).hexdigest
          end
          # Move only tracked files aside; restore them if committing the registry fails.
          Dir.mktmpdir(".wani-remove-", @root) do |stage|
            moved = []
            begin
              paths.each_with_index do |(_relative, path), index|
                next unless File.exist?(path)
                backup = File.join(stage, index.to_s)
                File.rename(path, backup)
                moved << [path, backup]
              end
              save(fonts.reject { |key, _| key == id })
            rescue Exception
              moved.reverse_each { |path, backup| File.rename(backup, path) }
              raise
            end
          end
          ["fonts/#{id}/files", "fonts/#{id}"].each do |relative|
            path = safe_path(relative)
            Dir.rmdir(path) if File.directory?(path) && Dir.empty?(path)
          end
        end
      end

      private

      def identify(source)
        if source.match?(%r{[:/\\]})
          uri = URI.parse(source)
          raise Error, "Use an official https://fontsource.org/fonts/ID URL" unless uri.scheme == "https" && uri.host == "fontsource.org" && uri.port == 443 && !uri.userinfo && !uri.query && !uri.fragment && uri.path.match?(%r{\A/fonts/[a-z0-9]+(?:-[a-z0-9]+)*/?\z})
          return uri.path.split('/').last
        end
        candidates = json("https://api.fontsource.org/v1/fonts")
        raise Error, "Invalid font catalog" unless candidates.is_a?(Array) && candidates.all? { |item| item.is_a?(Hash) && item['family'].is_a?(String) && item['id'].is_a?(String) }
        matches = candidates.select { |item| item['id'] == source || item.fetch('family').casecmp?(source) }
        matches = candidates.select { |item| item.fetch('family').downcase.include?(source.downcase) } if matches.empty?
        raise Error, "Font not found: #{source}" if matches.empty?
        raise Error, "Ambiguous font; specify an ID: #{matches.map { |item| item['id'] }.join(', ')}" unless matches.length == 1
        id = matches.first.fetch('id')
        raise Error, "Invalid Fontsource ID" unless Core::Fonts::ID.match?(id)
        id
      rescue URI::InvalidURIError
        raise Error, "Invalid Fontsource URL"
      end

      def download(url)
        body = @http.get(url)
        @bytes += body.bytesize
        raise Error, "Font exceeds 256 MiB installation limit" if @bytes > 256 * 1024 * 1024
        body
      end

      def json(url)
        JSON.parse(download(url))
      end

      def safe_path(relative)
        current = @root
        relative.split('/').each do |part|
          raise Error, "Unsafe project path" if part == '..' || part == '.' || part.empty?
          current = File.join(current, part)
          raise Error, "Symlinks are not allowed in managed font paths: #{relative}" if File.symlink?(current)
        end
        current
      end

      def locked
        FileUtils.mkdir_p(safe_path(".wani"))
        File.open(safe_path(".wani/fonts.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      def save(fonts)
        path = safe_path(".wani/fonts.yml")
        Tempfile.create(["fonts-", ".yml"], safe_path(".wani")) do |temporary|
          temporary.write(YAML.dump("fonts" => fonts))
          temporary.flush
          temporary.fsync
          File.rename(temporary.path, path)
        end
      end
    end
  end
end
