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
end
desc "Build the installable gem, including freshly packed browser assets"
task package: ["build:wasm", :test] do
  sh "gem", "build", "wani.gemspec"
end
