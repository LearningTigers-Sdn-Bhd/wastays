require "net/http"
require "json"

module Channex
  class Client
    class RetryableRequestError < StandardError; end

    STAGING_URL = "https://staging.channex.io/api/v1".freeze
    PRODUCTION_URL = "https://channex.io/api/v1".freeze

    def initialize(api_key: nil, environment: nil)
      @api_key = api_key || AppConfig.get("channex_api_key")

      env = environment || AppConfig.get("channex_environment") || "staging"
      @base_url = env == "production" ? PRODUCTION_URL : STAGING_URL
    end

    def get(path, params = {})
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      execute(request)
    end

    def post(path, body = {})
      uri = URI("#{@base_url}#{path}")
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json if body.present?

      execute(request)
    end

    def put(path, body = {})
      uri = URI("#{@base_url}#{path}")
      request = Net::HTTP::Put.new(uri)
      request.body = body.to_json if body.present?

      execute(request)
    end

    def delete(path)
      uri = URI("#{@base_url}#{path}")
      request = Net::HTTP::Delete.new(uri)

      execute(request)
    end

    private

    def execute(request)
      request["Content-Type"] = "application/json"
      request["user-api-key"] = @api_key

      uri = request.uri
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 10

      response = nil
      ActiveSupport::Notifications.instrument("request.faraday", {
        method: request.method,
        url: uri.to_s,
        request_headers: request.to_hash
      }) do |payload|
        response = http.request(request)
        payload[:status] = response.code.to_i
        payload[:response_headers] = response.to_hash
        payload[:body] = response.body
      end

      parse_response(response)
    rescue JSON::ParserError => e
      { error: "Invalid JSON response from Channex API", details: e.message }
    rescue StandardError => e
      { error: "Channex API connection failed", details: e.message, retryable: true }
    end

    def parse_response(response)
      body = JSON.parse(response.body) rescue {}

      if response.is_a?(Net::HTTPSuccess)
        body
      else
        status_code = response.code.to_i
        {
          error: "Channex API error: #{response.code}",
          status: response.code,
          details: body["errors"] || body["error"] || response.body,
          retryable: retryable_status?(status_code)
        }
      end
    end

    def retryable_status?(status_code)
      status_code == 429 || status_code >= 500
    end
  end
end
