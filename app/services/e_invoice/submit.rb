# frozen_string_literal: true

module EInvoice
  class Submit
    def self.call(target)
      new(target).call
    end

    def initialize(target)
      @submission = target.is_a?(EInvoiceSubmission) ? target : nil
      @booking = @submission&.booking || target
      raise ArgumentError, "Booking must have an associated hotel" unless @booking&.hotel

      @hotel = @booking.hotel
    end

    def call
      return error("Booking payment has not concluded.") unless payment_concluded?

      existing = submission_record
      return error("E-invoice already submitted with UUID: #{existing.uuid}") if existing&.validated?
      refresh_buyer_snapshot = existing&.invalid?

      submission = existing || EInvoiceSubmission.new(
        hotel:         @hotel,
        booking:       @booking,
        document_scenario: default_document_scenario,
        document_type: default_document_type
      )

      if existing
        submission.assign_attributes(
          document_scenario: scenario,
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
        context = EInvoice::SubmissionContext.for(@booking, document_scenario: scenario)
        if scenario != "payout_self_billed_invoice"
          submission.buyer_snapshot = EInvoice::BuyerSnapshot.capture(@booking) if refresh_buyer_snapshot || submission.buyer_snapshot.blank?
        end
        submission.assign_attributes(
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          supplier_name: context.supplier_name,
          supplier_tin: context.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin
        )
        submission.save!
        doc = builder_for(submission, context).build
        client = MyInvois::ClientFactory.build(
          mode: context.submission_mode.to_sym,
          represented_taxpayer_tin: context.represented_taxpayer_tin,
          setting: context.setting
        )
        response = client.submit_documents([ doc ])

        handle_response(submission, doc, response, context)
      rescue EInvoice::SubmissionContext::ConfigurationError => e
        submission.assign_attributes(
          submission_mode: inferred_submission_mode,
          fund_collector: @booking.resolved_fund_collector,
          status: "invalid",
          error_details: { message: e.message }
        )
        submission.save!
        error(e.message, submission: submission)
      rescue MyInvois::Client::ApiError => e
        # A transient fault says nothing about the document. Leave it pending
        # and let the job's retry_on back off, rather than burning it as
        # invalid and making staff re-file by hand.
        raise if e.transient?

        submission.assign_attributes(
          status:        "invalid",
          error_details: { message: e.message, code: e.code, body: truncated_error_body(e.body) }
        )
        submission.save!
        error(e.message, submission: submission)
      rescue => e
        Rails.logger.error("[EInvoice::Submit] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        submission.assign_attributes(
          status: "invalid",
          error_details: {
            message: e.message,
            exception_class: e.class.name
          }
        )
        submission.save!
        error(e.message, submission: submission)
      end
    end

    private

    def payment_concluded?
      @booking.payment_concluded?
    end

    def submission_record
      return @submission if @submission

      @booking.e_invoice_submissions.for_scenario(default_document_scenario).recent_first.first
    end

    def guest_invoice_scenario
      @booking.e_invoice_document_scenario
    end

    def scenario
      @submission&.document_scenario || guest_invoice_scenario
    end

    def default_document_scenario
      scenario
    end

    def default_document_type
      scenario == "payout_self_billed_invoice" ? "11" : "01"
    end

    def builder_for(submission, context)
      if scenario == "payout_self_billed_invoice"
        EInvoice::PayoutSelfBilledDocumentBuilder.new(submission, context: context)
      else
        EInvoice::DocumentBuilder.new(@booking, context: context, buyer_snapshot: submission.buyer_snapshot)
      end
    end

    def handle_response(submission, doc, response, context)
      accepted = Array(response.dig("acceptedDocuments")).first
      rejected = Array(response.dig("rejectedDocuments")).first

      if accepted
        submission.assign_attributes(
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          supplier_name: context.supplier_name,
          supplier_tin: context.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin,
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
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          supplier_name: context.supplier_name,
          supplier_tin: context.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin,
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
        submission.assign_attributes(
          status: "invalid",
          raw_response: response,
          error_details: { message: "Unexpected response from MyInvois", response: response }
        )
        submission.save!
        error("Unexpected response from MyInvois: #{response.inspect}", submission: submission)
      end
    end

    def error(message, submission: nil)
      { success: false, error: message, submission: submission }
    end

    def inferred_submission_mode
      scenario == "payout_self_billed_invoice" ? "taxpayer" : (@booking.resolved_fund_collector == "hotel" ? "intermediary" : "taxpayer")
    end

    def truncated_error_body(body)
      value = body.is_a?(String) ? body : body.to_json
      value.to_s.truncate(500)
    end
  end
end
