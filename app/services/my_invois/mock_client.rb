# frozen_string_literal: true

module MyInvois
  # Mock client for development and testing.
  # Returns realistic LHDN-shaped responses without making real HTTP calls.
  #
  # Activated when:
  #   Rails.application.credentials.dig(:myinvois, :environment) == "mock"
  #   OR ENV["MYINVOIS_MOCK"] == "true"
  #
  # Usage in development — add to credentials:
  #   myinvois:
  #     environment: "mock"
  #     tin: "C0000000000"
  #     brn: "000000000000"
  #     name: "Jesselton Pixel Sdn Bhd"
  #     ... (other fields still needed for document building)
  class MockClient
    class << self
      attr_accessor :submit_documents_override, :document_details_override

      def reset_overrides!
        self.submit_documents_override = nil
        self.document_details_override = nil
      end
    end

    def initialize(mode: :taxpayer, represented_taxpayer_tin: nil)
      @mode = mode.to_s
      @represented_taxpayer_tin = represented_taxpayer_tin
      Rails.logger.info("[MyInvois::MockClient] Using mock client — no real API calls will be made.")
    end

    def submit_documents(documents)
      return normalize_override(self.class.submit_documents_override, documents:) if self.class.submit_documents_override.present?

      doc = documents.first || {}
      code_number = doc[:codeNumber] || doc["codeNumber"] || "MOCK-INV-001"
      mock_uuid   = "MOCK-#{SecureRandom.hex(8).upcase}"
      mock_sub_uid = "MOCKSUB-#{SecureRandom.hex(6).upcase}"

      Rails.logger.info("[MyInvois::MockClient] submit_documents — codeNumber: #{code_number}, UUID: #{mock_uuid}")

      {
        "submissionUid"       => mock_sub_uid,
        "acceptedDocuments"   => [
          {
            "uuid"              => mock_uuid,
            "invoiceCodeNumber" => code_number
          }
        ],
        "authMode"            => @mode,
        "onBehalfOf"          => @represented_taxpayer_tin,
        "rejectedDocuments"   => []
      }
    end

    def get_submission(submission_uid)
      {
        "submissionUid"     => submission_uid,
        "status"            => "Valid",
        "documentCount"     => 1,
        "dateTimeReceived"  => Time.current.utc.iso8601
      }
    end

    def get_document_details(uuid)
      return normalize_override(self.class.document_details_override, uuid:) if self.class.document_details_override.present?

      mock_long_id = "MOCKLONG#{SecureRandom.hex(10).upcase}"

      Rails.logger.info("[MyInvois::MockClient] get_document_details — UUID: #{uuid}")

      {
        "uuid"                  => uuid,
        "submissionUid"         => "MOCKSUB-DETAIL",
        "longId"                => mock_long_id,
        "status"                => "Valid",
        "dateTimeIssued"        => Time.current.utc.iso8601,
        "dateTimeReceived"      => Time.current.utc.iso8601,
        "dateTimeValidated"     => Time.current.utc.iso8601
      }
    end

    def cancel_document(uuid, reason:)
      Rails.logger.info("[MyInvois::MockClient] cancel_document — UUID: #{uuid}, reason: #{reason}")
      { "uuid" => uuid, "status" => "Cancelled" }
    end

    # Confirmed against LHDN preprod: a match answers 200 with an empty body,
    # not a JSON payload with a status field. A mismatch is a 404, which is
    # raised as ApiError elsewhere, not returned from here.
    def validate_tin(tin, id_type:, id_value:)
      {}
    end

    private

    def normalize_override(override, **kwargs)
      override.respond_to?(:call) ? override.call(**kwargs) : override
    end
  end
end
