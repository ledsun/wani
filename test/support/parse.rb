require "json"
require_relative "../../lib/wani/core/parser"
begin
  puts JSON.generate(Wani::Core::Parser.new.parse($stdin.read).to_h)
rescue Wani::Core::Parser::Error => error
  puts JSON.generate({ error: error.message })
end
