require "json"
require_relative "../lib/wani/deck"

# JSON in, JSON out; no browser or JS dependencies required.
request = JSON.parse($stdin.read)
deck = Wani::Deck.new(request.fetch("markdown"))
snapshots = [deck.snapshot]
request.fetch("moves", []).each do |delta|
  snapshots << deck.move(Integer(delta)).snapshot
end
puts JSON.generate(snapshots)
