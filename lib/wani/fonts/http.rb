require "net/http"
require "uri"
require "timeout"

module Wani
  module Fonts
    class Error < ArgumentError; end

    class HTTP
      MAX_BYTES = 32 * 1024 * 1024
      def get(url, redirects: 3)
        uri = URI.parse(url)
        valid = uri.scheme == "https" && uri.port == 443 && !uri.userinfo && !uri.fragment && !uri.query
        valid &&= case uri.host
                  when "api.fontsource.org" then uri.path.match?(%r{\A/v1/(?:fonts|version)(?:/[a-z0-9-]+)?\z})
                  when "cdn.jsdelivr.net" then uri.path.match?(%r{\A/npm/@fontsource(?:-variable)?/[a-z0-9-]+@\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?/(?:package\.json|metadata\.json|LICENSE|[a-z0-9-]+\.css|files/[a-zA-Z0-9_-]+\.woff2)\z})
                  else false
                  end
        raise Error, "Untrusted Fontsource URL: #{url}" unless valid
        Timeout.timeout(60) do
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20, write_timeout: 20) do |http|
            http.request(Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding" => "identity")) do |response|
              if response.is_a?(Net::HTTPRedirection)
                raise Error, "Too many redirects" if redirects.zero?
                return get(URI.join(url, response.fetch("location")).to_s, redirects: redirects - 1)
              end
              raise Error, "Fontsource HTTP #{response.code}: #{url}" unless response.is_a?(Net::HTTPSuccess)
              expected = response["content-length"]&.to_i
              raise Error, "Download exceeds size limit" if expected && expected > MAX_BYTES
              body = +"".b
              response.read_body do |part|
                body << part
                raise Error, "Download exceeds size limit" if body.bytesize > MAX_BYTES
              end
              raise Error, "Incomplete download: #{url}" if body.empty? || (expected && expected != body.bytesize)
              return body
            end
          end
        end
      rescue URI::InvalidURIError, SocketError, IOError, SystemCallError, Timeout::Error, Net::HTTPError, OpenSSL::SSL::SSLError => error
        raise Error, "Fontsource download failed: #{error.message}"
      end
    end
  end
end
