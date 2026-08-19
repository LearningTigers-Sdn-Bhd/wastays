# frozen_string_literal: true

require "net/http"
require "json"

module MyInvois
  class Client
    ENVIRONMENTS = {
      "production" => "https://api.myinvois.hasil.gov.my",
      "sandbox" => "https://preprod-api.myinvois.hasil.gov.my"
    }.freeze

    class ApiError < StandardError
      # A rate limit or a fault on LHDN's side says nothing about the document,
      # so those are worth retrying. A 4xx is LHDN telling us the document or
      # our credentials are wrong, and retrying it just repeats the rejection.
      TRANSIENT_STATUSES = [ 408, 429 ].freeze

      attr_reader :code, :body

      def initialize(msg, code: nil, body: nil)
        super(msg)
        @code = code
        @body = body
      end

      def transient?
        return false if code.blank?

        status = code.to_i
        status >= 500 || TRANSIENT_STATUSES.include?(status)
      end
    end

    # Raised for network-level failures, which are always worth retrying.
    class TransportError < ApiError
      def transient?
        true
      end
    end

    TRANSPORT_ERRORS = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError, EOFError
    ].freeze

    # `setting` carries the filing hotel's own LHDN credentials. WAStays is
    # under the RM1m threshold and does not file as a supplier, so the normal
    # path authenticates as the hotel. The credentials-based path remains for
    # the intermediary case, which needs WAStays' own registration.
    def initialize(mode: :taxpayer, represented_taxpayer_tin: nil, setting: nil)
      @mode = mode.to_s
      @represented_taxpayer_tin = represented_taxpayer_tin.presence
      @setting = setting
      @environment = resolved_environment
      @base_url = ENVIRONMENTS.fetch(@environment, ENVIRONMENTS["sandbox"])
    end

    def submit_documents(documents)
      post("/api/v1.0/documentsubmissions", { documents: documents })
    end

    def get_submission(submission_uid)
      get("/api/v1.0/documentsubmissions/#{submission_uid}")
    end

    def get_document_details(uuid)
      get("/api/v1.0/documents/#{uuid}/details")
    end

    def cancel_document(uuid, reason:)
      put("/api/v1.0/documents/state/#{uuid}/state", { status: "cancelled", reason: reason })
    end

    def validate_tin(tin, id_type:, id_value:)
      get("/api/v1.0/taxpayer/validate/#{tin}?idType=#{id_type}&idValue=#{id_value}")
    end

    private

    def access_token
      config = credential_config
      MyInvois::TokenStore.fetch(
        tin: config.fetch(:taxpayer_tin),
        environment: @environment,
        mode: @mode,
        represented_taxpayer_tin: @represented_taxpayer_tin
      ) do
        authenticate(config)
      end
    end

    def resolved_environment
      return @setting.api_environment if @setting&.api_environment.present?

      Rails.application.credentials.dig(:myinvois, :environment).presence || "sandbox"
    end

    def credential_config
      # A hotel filing for itself uses its own registration end to end.
      return hotel_credential_config if hotel_filing?

      client_id = if intermediary?
        Rails.application.credentials.dig(:myinvois, :intermediary_client_id)
      else
        Rails.application.credentials.dig(:myinvois, :client_id)
      end

      client_secret = if intermediary?
        Rails.application.credentials.dig(:myinvois, :intermediary_client_secret)
      else
        Rails.application.credentials.dig(:myinvois, :client_secret)
      end

      taxpayer_tin = if intermediary?
        @represented_taxpayer_tin
      else
        Rails.application.credentials.dig(:myinvois, :tin).to_s
      end

      if client_id.blank? || client_secret.blank?
        raise ApiError, intermediary? ? "MyInvois intermediary credentials are not configured." : "MyInvois credentials are not configured."
      end

      if taxpayer_tin.blank?
        raise ApiError, "Represented taxpayer TIN is required for intermediary submission."
      end

      {
        client_id: client_id,
        client_secret: client_secret,
        taxpayer_tin: taxpayer_tin
      }
    end

    def hotel_filing?
      !intermediary? && @setting&.api_credentials_ready?
    end

    def hotel_credential_config
      tin = @setting.hotel_tin.to_s
      raise ApiError, "This hotel's LHDN tax number is missing." if tin.blank?

      {
        client_id: @setting.client_id,
        client_secret: @setting.client_secret,
        taxpayer_tin: tin
      }
    end

    def intermediary?
      @mode == "intermediary"
    end

    def authenticate(config)
      uri = URI("#{@base_url}/connect/token")
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["onbehalfof"] = @represented_taxpayer_tin if intermediary?
      request.set_form_data(
        "grant_type" => "client_credentials",
        "client_id" => config.fetch(:client_id),
        "client_secret" => config.fetch(:client_secret),
        "scope" => "InvoicingAPI"
      )

      response = http.request(request)
      body = safe_parse(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError.new("Authentication failed: #{body}", code: response.code, body: body)
      end

      { token: body["access_token"], expires_in: body["expires_in"].to_i }
    end

    def get(path)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Get.new(uri)
      authorize!(req)
      req["Accept"] = "application/json"
      execute(uri, req)
    end

    def post(path, body)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      authorize!(req)
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      execute(uri, req)
    end

    def put(path, body)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Put.new(uri)
      authorize!(req)
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      execute(uri, req)
    end

    def authorize!(request)
      request["Authorization"] = "Bearer #{access_token}"
      request["onbehalfof"] = @represented_taxpayer_tin if intermediary?
    end

    def execute(uri, request)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      response = begin
        http.request(request)
      rescue *TRANSPORT_ERRORS => e
        raise TransportError.new("MyInvois transport failure: #{e.class}: #{e.message}")
      end
      parsed = safe_parse(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError.new(
          "MyInvois API error #{response.code}: #{parsed.dig("error", "message") || response.body}",
          code: response.code,
          body: parsed
        )
      end

      parsed
    end

    def safe_parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      { "raw" => body }
    end
  end
end
