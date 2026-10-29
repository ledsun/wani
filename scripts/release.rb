require "open3"

module Wani
  class Release
    FILES = %w[lib/wani/version.rb Gemfile.lock README.md].freeze

    def run
      raise "Release requires the main branch" unless capture("git", "branch", "--show-current").strip == "main"
      raise "Commit or stash changes before releasing" unless capture("git", "status", "--porcelain").empty?

      originals = FILES.to_h { |path| [path, File.binread(path)] }
      version = originals.fetch(FILES.first).match(/VERSION = "(\d+\.\d+\.\d+)"/)&.captures&.first
      raise "Expected a major.minor.patch version" unless version

      next_version = version.split(".").tap { |parts| parts[2] = (parts[2].to_i + 1).to_s }.join(".")
      tag = "v#{next_version}"
      raise "Tag #{tag} already exists" if capture("git", "tag", "--list", tag).strip == tag

      begin
        File.write(FILES[0], originals.fetch(FILES[0]).sub(%(VERSION = "#{version}"), %(VERSION = "#{next_version}")))
        File.write(FILES[1], originals.fetch(FILES[1]).gsub("wani (#{version})", "wani (#{next_version})"))
        File.write(FILES[2], originals.fetch(FILES[2]).gsub("wani-#{version}.gem", "wani-#{next_version}.gem"))

        command "bundle", "exec", "rake", "package"
        command "npm", "test"
        command "bundle", "exec", "ruby", "scripts/smoke_package.rb"
        command "git", "diff", "--check"
      rescue StandardError
        originals.each { |path, content| File.binwrite(path, content) }
        raise
      end

      command "git", "add", "--", *FILES
      command "git", "commit", "-m", "Release #{tag}"
      command "git", "tag", "-a", tag, "-m", "Release #{tag}"
      command "git", "push", "--atomic", "origin", "HEAD:refs/heads/main", "refs/tags/#{tag}"
      puts "Pushed #{tag}. GitHub Actions will test and publish the gem to RubyGems.org."
    end

    private

    def capture(*args)
      output, status = Open3.capture2(*args)
      raise "Command failed: #{args.join(' ')}" unless status.success?
      output
    end

    def command(*args)
      puts args.join(" ")
      raise "Command failed: #{args.join(' ')}" unless system(*args)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Dir.chdir(File.expand_path("..", __dir__)) do
    begin
      Wani::Release.new.run
    rescue StandardError => error
      abort error.message
    end
  end
end
