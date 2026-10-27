require "js"
begin
  $LOAD_PATH.unshift("/wani/bundle/kramdown/lib", "/wani/bundle/rexml/lib", "/wani/bundle/kramdown-parser-gfm/lib", "/wani/bundle/rouge/lib")
  require "/wani/lib/wani/browser/application"
  Wani::Browser::Application.new.start
rescue LoadError, StandardError => error
  document = JS.global[:document]
  document.getElementById("status")[:textContent] = "起動失敗: #{error.message}"
end
