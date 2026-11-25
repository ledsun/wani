require "rake/testtask"
Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.pattern = "test/ruby/**/*_test.rb"
end
task default: :test
namespace :build do
  task :wasm do
    ruby "scripts/build_wasm.rb"
  end
  desc "Detect native extensions and build a smaller browser WASM"
  task :wasm_minimal do
    ruby "scripts/build_wasm.rb", "--minimal"
  end
end
desc "Build the installable gem, including freshly packed browser assets"
task package: ["build:wasm", :test] do
  sh "gem", "build", "wani.gemspec"
end
namespace :package do
  desc "Build the installable gem with the minimal browser WASM"
  task minimal: ["build:wasm_minimal", :test] do
    sh "gem", "build", "wani.gemspec"
  end
end

desc "Test, bump the patch version, commit, and push a release tag to origin"
task :release do
  ruby "scripts/release.rb"
end
