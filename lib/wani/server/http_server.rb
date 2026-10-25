require "webrick"
require_relative "application"

module Wani
  module Server
    class HTTPServer
      def initialize(file, bind: "127.0.0.1", port: 8000, out: $stdout)
        app = Application.new(file)
        @server = WEBrick::HTTPServer.new(BindAddress: bind, Port: port,
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), AccessLog: [],
          StartCallback: -> { out.puts "Wani: http://#{bind.include?(':') ? "[#{bind}]" : bind}:#{@server.listeners.first.addr[1]}/"; out.flush })
        @server.mount_proc("/") do |request, response|
          if %w[GET HEAD].include?(request.request_method)
            status, headers, body = app.call(request.unparsed_uri)
            response.status = status
            headers.each { |key, value| response[key] = value }
            response.body = body
          else
            response.status = 405
            response["Allow"] = "GET, HEAD"
          end
        end
      end

      def start
        previous = %w[INT TERM].to_h { |signal| [signal, Signal.trap(signal) { @server.shutdown }] }
        @server.start
      ensure
        previous&.each { |signal, handler| Signal.trap(signal, handler) }
        @server.shutdown
      end
    end
  end
end
