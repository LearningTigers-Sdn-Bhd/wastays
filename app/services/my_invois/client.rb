# frozen_string_literal: true

require "net/http"
require "json"
require "digest"
require "base64"

module MyInvois
  # HTTP client for the LHDN MyInvois API.
  #
  # WAStays (Jesselton Pixel Sdn Bhd) is the taxpayer — we authenticate as
  # "Login as Taxpayer System" using WAStays' own Client ID + Secret.
  # No intermediary setup is needed since WAStays is the invoice issuer on all documents.
  #
  # Credentials are read from Rails.application.credentials.myinvois:
  #   client_id:   "..."
  #   client_secret: "..."
  #   tin:         "C?????????"   (WAStays TIN)
  #   environment: "production" | "sandbox"
  class Client
    ENVIRONMENTS = {
      "production" => "https://api.myinvois.hasil.gov.my",
      "sandbox"    => "https://preprod-api.myinvois.hasil.gov.my"
    }.freeze

    class ApiError < StandardError
      attr_reader :code, :body
      def initialize(msg, code: nil, body: nil)
        super(msg)
        @code = code
        @body = body
      end
    end

    def initialize
      @environment = Rails.application.credentials.dig(:myinvois, :environment).presence || "production"
      @base_url    = ENVIRONMENTS.fetch(@environment, ENVIRONMENTS["production"])
    end

    # Submit one or more documents to MyInvois.
    # documents: array of hashes — { format:, document:, documentHash:, codeNumber: }
    def submit_documents(documents)
      post("/api/v1.0/documentsubmissions", { documents: documents })
    end

    # Poll status of a submission batch by submissionUid
    def get_submission(submission_uid)
      get("/api/v1.0/documentsubmissions/#{submission_uid}")
    end

    # Get full details of a single document by LHDN UUID
    def get_document_details(uuid)
      get("/api/v1.0/documents/#{uuid}/details")
    end

    # Cancel a previously submitted (valid) document
    def cancel_document(uuid, reason:)
      put("/api/v1.0/documents/state/#{uuid}/state", { status: "cancelled", reason: reason })
    end

    # Validate a taxpayer's TIN before using it on an invoice
    def validate_tin(tin, id_type:, id_value:)
      get("/api/v1.0/taxpayer/validate/#{tin}?idType=#{id_type}&idValue=#{id_value}")
    end

    private

    def access_token
      tin         = Rails.application.credentials.dig(:myinvois, :tin).to_s
      MyInvois::TokenStore.fetch(tin: tin, environment: @environment) do
        authenticate
      end
    end

    # Login as Taxpayer System — WAStays' own account, no intermediary.
    def authenticate
      client_id     = Rails.application.credentials.dig(:myinvois, :client_id)
      client_secret = Rails.application.credentials.dig(:myinvois, :client_secret)

      raise ApiError, "MyInvois credentials not configured. Run: bin/rails credentials:edit" \
        if client_id.blank? || client_secret.blank?

      uri  = URI("#{@base_url}/connect/token")
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.set_form_data(
        "grant_type"    => "client_credentials",
        "client_id"     => client_id,
        "client_secret" => client_secret,
        "scope"         => "InvoicingAPI"
        # No "onbehalfof" — WAStays submits as itself (Taxpayer System, not Intermediary)
      )

      response = http.request(request)
      body     = safe_parse(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError.new("Authentication failed: #{body}", code: response.code, body: body)
      end

      { token: body["access_token"], expires_in: body["expires_in"].to_i }
    end

    def get(path)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Accept"]        = "application/json"
      execute(uri, req)
    end

    def post(path, body)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"]  = "application/json"
      req.body             = body.to_json
      execute(uri, req)
    end

    def put(path, body)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Put.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"]  = "application/json"
      req.body             = body.to_json
      execute(uri, req)
    end

    def execute(uri, request)
      http              = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl      = true
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(request)
      parsed   = safe_parse(response.body)

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
