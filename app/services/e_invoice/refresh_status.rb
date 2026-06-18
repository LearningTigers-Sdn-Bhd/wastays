# frozen_string_literal: true

module EInvoice
  # Polls MyInvois for the current validation status of a submitted document.
  class RefreshStatus
    def self.call(submission)
      new(submission).call
    end

    def initialize(submission)
      @submission = submission
    end

    def call
      return { success: false, error: "No UUID to poll." } if @submission.uuid.blank?

      client   = MyInvois::ClientFactory.build
      response = client.get_document_details(@submission.uuid)

      new_status = map_status(response["status"])
      long_id    = response["longId"]

      @submission.update!(
        status:       new_status,
        long_id:      long_id,
        raw_response: @submission.raw_response.merge("details" => response),
        validated_at: (Time.current if new_status == "valid")
      )

      { success: true, submission: @submission }
    rescue MyInvois::Client::ApiError => e
      { success: false, error: e.message }
    end

    private

    # LHDN status strings: "Submitted", "Valid", "Invalid", "Cancelled"
    def map_status(lhdn_status)
      case lhdn_status.to_s
      when "Valid"     then "valid"
      when "Invalid"   then "invalid"
      when "Cancelled" then "cancelled"
      when "Submitted" then "submitted"
      else @submission.status
      end
    end
  end
end
