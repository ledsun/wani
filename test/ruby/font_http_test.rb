require_relative "test_helper"
require "wani/fonts/http"

class FontHTTPTest < Minitest::Test
  def with_response(response, body = '')
    response.define_singleton_method(:read_body) { |&block| block.call(body) }
    client = Object.new
    client.define_singleton_method(:request) { |_request, &block| block.call(response) }
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_, **_, &block| block.call(client) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  def test_redirect_target_is_validated
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['location'] = 'https://evil.test/font.woff2'
    with_response(response) do
      assert_raises(Wani::Fonts::Error) { Wani::Fonts::HTTP.new.get('https://api.fontsource.org/v1/fonts') }
    end
  end

  def test_http_errors_truncation_and_size_limit
    response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    with_response(response) do
      assert_raises(Wani::Fonts::Error) { Wani::Fonts::HTTP.new.get('https://api.fontsource.org/v1/fonts') }
    end
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    [10, Wani::Fonts::HTTP::MAX_BYTES + 1].each do |length|
      response['content-length'] = length.to_s
      with_response(response, 'short') do
        assert_raises(Wani::Fonts::Error) { Wani::Fonts::HTTP.new.get('https://api.fontsource.org/v1/fonts') }
      end
    end
  end
end
