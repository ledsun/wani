require_relative "lib/wani/version"
Gem::Specification.new do |spec|
  spec.name = "wani"
  spec.version = Wani::VERSION
  spec.summary = "Markdown presentations rendered by Ruby in the browser"
  spec.authors = ["ledsun"]
  spec.homepage = "https://github.com/ledsun/wani"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "exe/*", "assets/**/*", "templates/**/*", "third_party/**/*", "README.md", "LICENSE"].select { |file| File.file?(file) }
  spec.bindir = "exe"
  spec.executables = ["wani"]
  spec.require_paths = ["lib"]
  spec.add_dependency "kramdown", "= 2.5.2"
  spec.add_dependency "kramdown-parser-gfm", "= 1.1.0"
  spec.add_dependency "rexml", "= 3.4.4"
  spec.add_dependency "webrick", "~> 1.9"
  spec.metadata["source_code_uri"] = spec.homepage
end
