require "optparse"
require "fileutils"
require_relative "../wani"

module Wani
  class CLI
    def initialize(out: $stdout, err: $stderr)
      @out, @err = out, err
    end

    def run(arguments)
      args = arguments.dup
      command = args.shift
      case command
      when "new" then create(args)
      when "serve" then serve(args)
      when "check" then check(args)
      when "--version", "-v" then @out.puts(VERSION); 0
      when nil, "--help", "-h", "help" then @out.puts("Usage: wani new DIRECTORY | serve [FILE] [--bind ADDRESS] [--port PORT] | check [FILE]"); 0
      else raise ArgumentError, "Unknown command: #{command}"
      end
    rescue ArgumentError, OptionParser::ParseError, SystemCallError => error
      @err.puts "wani: #{error.message}"
      1
    end

    private

    def create(args)
      raise ArgumentError, "Usage: wani new DIRECTORY" unless args.length == 1
      destination = File.expand_path(args.first)
      Dir.mkdir(destination) # Atomic refusal, including existing directories and symlinks.
      Dir.mkdir(File.join(destination, "images"))
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
      issues.each { |issue| @out.puts "#{issue.severity}: #{issue.slide ? "slide #{issue.slide}: " : ""}#{issue.message}" }
      @out.puts "#{presentation.slides.length} slides; #{issues.length} diagnostics"
      issues.any? { |issue| issue.severity == :error } ? 1 : 0
    rescue Core::Parser::Error => error
      @err.puts "error: #{error.message}"
      1
    end
  end
end
