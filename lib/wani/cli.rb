require "optparse"
require "fileutils"
require_relative "../wani"

module Wani
  class CLI
    def initialize(out: $stdout, err: $stderr, font_manager: nil)
      @out, @err = out, err
      @font_manager = font_manager
    end

    def run(arguments)
      args = arguments.dup
      command = args.shift
      case command
      when "new" then create(args)
      when "font" then font(args)
      when "serve" then serve(args)
      when "check" then check(args)
      when "--version", "-v" then @out.puts(VERSION); 0
      when nil, "--help", "-h", "help" then @out.puts("Usage: wani new DIRECTORY | serve [FILE] [--bind ADDRESS] [--port PORT] | check [FILE] | font add SOURCE | font list | font remove ID"); 0
      else raise ArgumentError, "Unknown command: #{command}"
      end
    rescue ArgumentError, OptionParser::ParseError, SystemCallError => error
      @err.puts "wani: #{error.message}"
      1
    end

    private

    def font(args)
      require_relative "fonts/manager"
      manager = @font_manager || Fonts::Manager.new
      action = args.shift
      case action
      when "add"
        raise ArgumentError, "Usage: wani font add SOURCE" unless args.length == 1
        entry = with_font_progress { manager.add(args.first) }
        @out.puts "Installed #{entry['family']} (#{entry['version']}); set font in Markdown to apply it."
      when "list"
        raise ArgumentError, "Usage: wani font list" unless args.empty?
        @out.puts "ID\tFamily\tVersion\tVariable"
        manager.list.each { |id, entry| @out.puts [id, entry['family'], entry['version'], entry['variable']].join("\t") }
      when "remove"
        raise ArgumentError, "Usage: wani font remove ID" unless args.length == 1
        manager.remove(args.first, confirm: ->(files) {
          @err.puts "Warning: font is used by #{files.join(', ')}"
          next false unless $stdin.tty?
          @err.print "Remove this font? [y/N] "
          $stdin.gets&.strip&.downcase == "y"
        })
        @out.puts "Removed #{args.first}"
      else
        raise ArgumentError, "Usage: wani font add SOURCE | list | remove ID"
      end
      0
    end

    def with_font_progress
      message = "Downloading font"
      if @err.tty?
        @err.print "\r#{message}.  "
        @err.flush
        animation = Thread.new do
          dots = 1
          loop do
            sleep 0.3
            dots = dots % 3 + 1
            @err.print "\r#{message}#{('.' * dots).ljust(3)}"
            @err.flush
          end
        end
      else
        @err.puts "#{message}..."
        @err.flush
      end
      yield
    ensure
      if animation
        animation.kill
        animation.join
        @err.print "\r#{' ' * (message.length + 3)}\r"
        @err.flush
      end
    end

    def create(args)
      raise ArgumentError, "Usage: wani new DIRECTORY" unless args.length == 1
      destination = File.expand_path(args.first)
      Dir.mkdir(destination) # Atomic refusal, including existing directories and symlinks.
      FileUtils.cp_r(File.join(ROOT, "templates/images"), File.join(destination, "images"))
      FileUtils.cp(File.join(ROOT, "templates/slides.md"), File.join(destination, "slides.md"))
      @out.puts "Created #{args.first}. Run: cd #{args.first} && wani serve"
      0
    end

    def serve(args)
      options = { bind: "127.0.0.1", port: 8000, out: @out }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: wani serve [FILE] [--bind ADDRESS] [--port PORT]"
        opts.on("-b", "--bind ADDRESS") { |value| options[:bind] = value }
        opts.on("-p", "--port PORT", Integer) { |value| options[:port] = value }
      end
      parser.parse!(args)
      raise ArgumentError, parser.banner if args.length > 1
      raise ArgumentError, "Port must be between 0 and 65535" unless (0..65535).cover?(options[:port])
      raise ArgumentError, "Browser assets missing; run bundle exec rake build:wasm before gem build" unless File.file?(File.join(ROOT, "assets/wani.wasm"))
      require_relative "server/http_server"
      Server::HTTPServer.new(args.first || "slides.md", **options).start
      0
    end

    def check(args)
      require_relative "core/parser"
      require_relative "core/validator"
      raise ArgumentError, "Usage: wani check [FILE]" if args.length > 1
      file = File.expand_path(args.first || "slides.md")
      presentation = Core::Parser.new.parse(File.read(file, encoding: "UTF-8"))
      issues = Core::Validator.new.validate(presentation, base_dir: File.dirname(file))
      if (name = presentation.fonts["default"])
        require_relative "fonts/manager"
        unless Core::Fonts.resolve(Fonts::Manager.new(File.dirname(file)).list, name)
          issues << Core::Diagnostic.new(severity: :warning, message: "Unregistered font: #{name}; using fallback")
        end
      end
      issues.each { |issue| @out.puts "#{issue.severity}: #{issue.slide ? "slide #{issue.slide}: " : ""}#{issue.message}" }
      @out.puts "#{presentation.slides.length} slides; #{issues.length} diagnostics"
      issues.any? { |issue| issue.severity == :error } ? 1 : 0
    rescue Core::Parser::Error => error
      @err.puts "error: #{error.message}"
      1
    end
  end
end
