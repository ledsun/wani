require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/release"

class ReleaseTest < Minitest::Test
  class FakeRelease < Wani::Release
    attr_accessor :branch, :dirty, :existing_tag, :failure
    attr_reader :commands, :tested_version

    def initialize
      @branch = "main"
      @commands = []
    end

    private

    def capture(*args)
      case args[1]
      when "branch" then branch
      when "status" then dirty ? " M README.md\n" : ""
      when "tag" then existing_tag ? args.last : ""
      else raise "Unexpected command: #{args.inspect}"
      end
    end

    def command(*args)
      @commands << args
      @tested_version = File.read("lib/wani/version.rb") if args == %w[bundle exec rake package]
      raise "Simulated failure" if args.include?(failure)
    end
  end

  def setup
    @directory = Dir.mktmpdir("wani-release-test-")
    @original_directory = Dir.pwd
    FileUtils.mkdir_p(File.join(@directory, "lib/wani"))
    File.write(File.join(@directory, "lib/wani/version.rb"), "module Wani\n  VERSION = \"1.2.9\"\nend\n")
    File.write(File.join(@directory, "Gemfile.lock"), "    wani (1.2.9)\n  wani (1.2.9)\n")
    File.write(File.join(@directory, "README.md"), "gem install ./wani-1.2.9.gem\n")
    Dir.chdir(@directory)
    @release = FakeRelease.new
  end

  def teardown
    Dir.chdir(@original_directory)
    FileUtils.remove_entry(@directory)
  end

  def test_release_tests_updated_version_before_committing_and_pushing
    capture_io { @release.run }
    assert_includes @release.tested_version, 'VERSION = "1.2.10"'
    assert_equal "    wani (1.2.10)\n  wani (1.2.10)\n", File.read("Gemfile.lock")
    assert_equal "gem install ./wani-1.2.10.gem\n", File.read("README.md")
    assert_equal [
      %w[bundle exec rake package],
      %w[npm test],
      %w[bundle exec ruby scripts/smoke_package.rb],
      %w[git diff --check],
      ["git", "add", "--", *Wani::Release::FILES],
      ["git", "commit", "-m", "Release v1.2.10"],
      ["git", "tag", "-a", "v1.2.10", "-m", "Release v1.2.10"],
      %w[git push --atomic origin HEAD:refs/heads/main refs/tags/v1.2.10]
    ], @release.commands
  end

  def test_failed_checks_restore_files_and_never_commit
    %w[package test scripts/smoke_package.rb --check].each do |failure|
      originals = Wani::Release::FILES.to_h { |path| [path, File.binread(path)] }
      @release = FakeRelease.new
      @release.failure = failure
      assert_raises(RuntimeError) { @release.run }
      originals.each { |path, content| assert_equal content, File.binread(path) }
      refute @release.commands.any? { |args| args.include?("commit") || args.include?("push") }
    end
  end

  def test_rejects_dirty_tree_wrong_branch_and_existing_tag_before_changes
    [[:dirty, true], [:branch, "feature"], [:existing_tag, true]].each do |setting, value|
      @release = FakeRelease.new
      @release.public_send("#{setting}=", value)
      assert_raises(RuntimeError) { @release.run }
      assert_empty @release.commands
      assert_includes File.read("lib/wani/version.rb"), 'VERSION = "1.2.9"'
    end
  end

  def test_failed_push_keeps_release_version_for_retry
    @release.failure = "push"
    assert_raises(RuntimeError) { @release.run }
    assert_includes File.read("lib/wani/version.rb"), 'VERSION = "1.2.10"'
  end
end
