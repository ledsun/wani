require "json"
require_relative "../lib/parser"
begin
  puts JSON.generate(Preflight::Parser.new.parse($stdin.read))
rescue Preflight::Parser::Error => error
  puts JSON.generate({ "error" => error.message })
end
