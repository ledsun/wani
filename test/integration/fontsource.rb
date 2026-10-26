# Explicit opt-in network test; never loaded by rake test.
require "bundler/setup"
require_relative "../../lib/wani/fonts/manager"
require_relative "../../lib/wani/cli"
abort "Usage: bundle exec ruby test/integration/fontsource.rb NEW_DIRECTORY" unless ARGV.length == 1
root = File.expand_path(ARGV.first)
abort 'Could not create project' unless Wani::CLI.new.run(['new', root]).zero?
Dir.chdir(root) do
  abort 'Installation failed' unless Wani::CLI.new.run(['font', 'add', 'Noto Sans JP']).zero?
  Wani::CLI.new.run(['font', 'list'])
  manager = Wani::Fonts::Manager.new
  entry = manager.list.fetch('noto-sans-jp')
  css = File.read(entry.fetch('stylesheet'))
  abort 'Missing Japanese split subsets' unless css.scan('unicode-range:').length > 100
  abort 'Missing license' unless File.size(entry.fetch('license')) > 100
  entry.fetch('sha256').each { |file, hash| abort "Checksum mismatch: #{file}" unless Digest::SHA256.file(file).hexdigest == hash }
  File.write('slides.md', "---\nfont: Noto Sans JP\n---\n# 日本語プレゼンテーション\n\n漢字・ひらがな・カタカナと English 123。\n\n**太字の本文**\n\n---\n\n# 隠れたスライド\n\n𠮷野家と髙橋\n\n<!-- notes: 日本語のノート -->\n")
  puts "Verified #{entry['files'].length} files in #{root}"
end
