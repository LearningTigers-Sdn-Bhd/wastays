# frozen_string_literal: true

module EInvoice
  # Submits an e-invoice to LHDN MyInvois for a completed booking.
  #
  # WAStays (Jesselton Pixel Sdn Bhd) is the supplier on this invoice.
  # The guest is the buyer. Requires a closed BookingFolio.
  #
  # Usage:
  #   result = EInvoice::Submit.call(booking)
  #   result[:success]    # => true/false
  #   result[:submission] # => EInvoiceSubmission record
  #   result[:error]      # => error string on failure
  class Submit
    def self.call(booking)
      new(booking).call
    end

    def initialize(booking)
      @booking = booking
      @hotel   = booking.hotel
    end

    def call
      return error("Booking does not have a closed folio.") unless folio_closed?

      existing = @booking.e_invoice_submission
      return error("E-invoice already submitted with UUID: #{existing.uuid}") if existing&.validated?

      submission = existing || EInvoiceSubmission.new(
        hotel:         @hotel,
        booking:       @booking,
        document_type: "01"
      )

      if existing
        submission.assign_attributes(
          status:         "pending",
          uuid:           nil,
          long_id:        nil,
          submission_uid: nil,
          submitted_at:   nil,
          validated_at:   nil,
          cancelled_at:   nil,
          raw_response:   {},
          error_details:  {}
        )
      end

      begin
        doc      = EInvoice::DocumentBuilder.new(@booking).build
        client   = MyInvois::ClientFactory.build
        response = client.submit_documents([ doc ])

        handle_response(submission, doc, response)
      rescue MyInvois::Client::ApiError => e
        submission.assign_attributes(
          status:        "invalid",
          error_details: { message: e.message, code: e.code, body: e.body }
        )
        submission.save
        error(e.message, submission: submission)
      rescue => e
        Rails.logger.error("[EInvoice::Submit] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        error(e.message, submission: submission)
      end
    end

    private

    def folio_closed?
      @booking.booking_folio&.status == "closed"
    end

    def handle_response(submission, doc, response)
      accepted = Array(response.dig("acceptedDocuments")).first
      rejected = Array(response.dig("rejectedDocuments")).first

      if accepted
        submission.assign_attributes(
          internal_id:    doc[:codeNumber],
          uuid:           accepted["uuid"],
          submission_uid: response["submissionUid"],
          status:         "submitted",
          submitted_at:   Time.current,
          raw_response:   response
        )
        submission.save!
        { success: true, submission: submission }
      elsif rejected
        error_details = rejected.dig("error", "details") || []
        submission.assign_attributes(
          internal_id:    doc[:codeNumber],
          submission_uid: response["submissionUid"],
          status:         "invalid",
          raw_response:   response,
          error_details:  { rejected: rejected }
        )
        submission.save!
        error(
          "Submission rejected: #{error_details.map { |e| e["message"] }.join(", ")}",
          submission: submission
        )
      else
        error("Unexpected response from MyInvois: #{response.inspect}", submission: submission)
      end
    end

    def error(message, submission: nil)
      { success: false, error: message, submission: submission }
    end
  end
end
