# frozen_string_literal: true

require "net/http"
require "json"

module AroundThat
  # Checks that the stored AroundThat settings reach the API.
  #
  # It does not read a payload. A reply proves the host resolves, and the
  # status code says whether the API key was accepted. That is all an admin
  # needs before saving the settings.
  class TestConnection
    # The API root has no route, so the probe asks a real endpoint. /places is a
    # read endpoint that answers 401 without a credential, which makes it a
    # cheap proof of both the host and the key.
    PROBE_PATH = "places"

    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = 10

    Result = Struct.new(:success, :message, keyword_init: true) do
      def success? = success
    end

    def initialize(api_key: nil, base_url: nil, environment: nil)
      @api_key = (api_key || AppConfig.get("aroundthat_api_key")).to_s.strip
      @base_url = (base_url || AppConfig.get("aroundthat_base_url")).to_s.strip
      @environment = (environment || AppConfig.get("aroundthat_environment")).presence || "staging"
    end

    def call
      return failure("Base URL is missing.") if @base_url.blank?
      return failure("API key is missing.") if @api_key.blank?

      uri = probe_uri
      return failure("Base URL must be an http or https address.") unless uri.is_a?(URI::HTTP)

      classify(uri, perform(uri))
    rescue URI::InvalidURIError
      failure("Base URL is not a valid address.")
    rescue StandardError => e
      failure("Connection failed: #{e.message}")
    end

    private

    def probe_uri
      URI.parse("#{@base_url.delete_suffix('/')}/#{PROBE_PATH}")
    end

    def perform(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT_SECONDS
      http.read_timeout = READ_TIMEOUT_SECONDS
      http.request(request)
    end

    def classify(uri, response)
      code = response.code.to_i
      return success("AroundThat answered at #{uri.host} (#{@environment}).") if code.between?(200, 299)

      reported = reported_error(response)
      return failure("AroundThat refused the request: #{reported}") if reported

      case code
      when 401, 403 then failure("AroundThat reached #{uri.host}, but rejected the API key.")
      when 404 then failure("AroundThat reached #{uri.host}, but #{uri.path} returned 404. Check the base URL.")
      else failure("AroundThat reached #{uri.host}, but returned HTTP #{code}.")
      end
    end

    # AroundThat answers a failure with { "error": { "code", "message" } }. Its
    # own message names the real cause, such as a missing capability, which a
    # status code on its own cannot. A reply that is not an error document
    # leaves the status-based message in place.
    def reported_error(response)
      error = JSON.parse(response.body.to_s)["error"]
      return unless error.is_a?(Hash)

      message = error["message"].to_s.strip.presence
      code = error["code"].to_s.strip.presence
      return unless message || code

      [ message, ("(#{code})" if code) ].compact.join(" ")
    rescue JSON::ParserError, TypeError
      nil
    end

    def success(message) = Result.new(success: true, message: message)
    def failure(message) = Result.new(success: false, message: message)
  end
end
