# frozen_string_literal: true

require "net/http"

module AroundThat
  # Checks that the stored AroundThat settings reach the API.
  #
  # It does not read a payload. A reply proves the host resolves, and the
  # status code says whether the API key was accepted. That is all an admin
  # needs before saving the settings.
  class TestConnection
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

      uri = URI.parse(@base_url)
      return failure("Base URL must be an http or https address.") unless uri.is_a?(URI::HTTP)

      classify(uri, perform(uri))
    rescue URI::InvalidURIError
      failure("Base URL is not a valid address.")
    rescue StandardError => e
      failure("Connection failed: #{e.message}")
    end

    private

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

      case code
      when 200..299 then success("AroundThat answered at #{uri.host} (#{@environment}).")
      when 401, 403 then failure("AroundThat reached #{uri.host}, but rejected the API key.")
      when 404 then failure("AroundThat reached #{uri.host}, but the path returned 404. Check the base URL.")
      else failure("AroundThat reached #{uri.host}, but returned HTTP #{code}.")
      end
    end

    def success(message) = Result.new(success: true, message: message)
    def failure(message) = Result.new(success: false, message: message)
  end
end
