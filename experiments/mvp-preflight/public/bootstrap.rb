require "js"
begin
  require "/app/application"
  Preflight::Application.new.start
rescue LoadError, StandardError => error
  JS.global[:document].getElementById("status")[:textContent] = "ERROR: #{error.class}: #{error.message}"
  raise
end
