# frozen_string_literal: true

module EInvoice
  class IssueAdjustment
    Result = Struct.new(
      :needed?,
      :document_type,
      :delta,
      :message,
      keyword_init: true
    )

    def self.call(booking)
      new(booking).call
    end

    def self.preview(booking)
      new(booking).preview
    end

    def initialize(booking)
      @booking = booking
    end

    def preview
      folio = @booking.booking_folio
      return Result.new(needed?: false, message: "Adjustment notes are available after the folio is closed.") unless folio
      return Result.new(needed?: false, message: "Adjustment notes are available after the folio is closed.") unless folio.status == "closed"

      original = @booking.e_invoice_submissions
                         .guest_facing
                         .valid
                         .where(document_type: "01")
                         .recent_first
                         .first
      return Result.new(needed?: false, message: "Adjustment notes become available after the original e-invoice is validated.") unless original

      folio_total = calculate_folio_total(folio)
      original_amount = compute_original_amount(original)
      delta = folio_total - original_amount

      if delta.zero?
        Result.new(needed?: false, delta: delta, message: "No adjustment note is needed because the closed folio still matches the original e-invoice total.")
      else
        Result.new(
          needed?: true,
          document_type: delta.positive? ? "03" : "02",
          delta: delta,
          message: delta.positive? ? "Closed folio is higher than the original e-invoice. A debit note is needed." : "Closed folio is lower than the original e-invoice. A credit note is needed."
        )
      end
    end

    def call
      folio = @booking.booking_folio
      return skip("No folio to adjust.") unless folio
      return skip("Folio is not closed.") unless folio.status == "closed"

      original = @booking.e_invoice_submissions
                         .guest_facing
                         .valid
                         .where(document_type: "01")
                         .recent_first
                         .first
      return skip("No valid original e-invoice exists for this booking.") unless original

      folio_total = calculate_folio_total(folio)
      original_amount = compute_original_amount(original)
      delta = folio_total - original_amount

      return skip("No adjustment needed — folio matches original invoice.") if delta.zero?

      document_type = delta.positive? ? "03" : "02"

      existing_adjustment = @booking.e_invoice_submissions
                                     .where(document_type: document_type)
                                     .where.not(status: "cancelled")
                                     .first
      return skip("#{document_type == "03" ? "Debit" : "Credit"} note already exists for this booking.") if existing_adjustment&.validated?

      submission = existing_adjustment || EInvoiceSubmission.new(
        hotel: @booking.hotel,
        booking: @booking,
        document_scenario: original.document_scenario,
        document_type: document_type,
        original_invoice_internal_id: original.internal_id
      )

      return skip("Adjustment already in progress.") if submission.persisted? && submission.status.in?(%w[pending submitted])

      context = EInvoice::SubmissionContext.for(@booking, document_scenario: original.document_scenario)
      builder = EInvoice::AdjustmentNoteBuilder.new(
        booking: @booking,
        original_submission: original,
        adjustment_amount: delta,
        document_type: document_type
      )
      doc = builder.build

      client = MyInvois::ClientFactory.build(
        mode: context.submission_mode.to_sym,
        represented_taxpayer_tin: context.represented_taxpayer_tin
      )
      response = client.submit_documents([ doc ])

      handle_response(submission, doc, response, context, original)
    rescue EInvoice::SubmissionContext::ConfigurationError => e
      error_result(e.message)
    rescue MyInvois::Client::ApiError => e
      error_result(e.message)
    rescue => e
      Rails.logger.error("[EInvoice::IssueAdjustment] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      error_result(e.message)
    end

    private

    def calculate_folio_total(folio)
      charges = FolioTransaction.charge.where(booking_folio_id: folio.id).sum(:amount).to_d
      adjustments = FolioTransaction.adjustment.where(booking_folio_id: folio.id).sum(:amount).to_d
      charges + adjustments
    end

    def compute_original_amount(submission)
      raw = submission.raw_response
      total = raw.dig("acceptedDocuments", 0, "totalExcludingTax") ||
              raw.dig("acceptedDocuments", 0, "totalIncludingTax")
      return total.to_d if total

      @booking.total_amount.to_d
    end

    def handle_response(submission, doc, response, context, original)
      accepted = Array(response.dig("acceptedDocuments")).first
      rejected = Array(response.dig("rejectedDocuments")).first

      if accepted
        submission.assign_attributes(
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          supplier_name: context.supplier_name,
          supplier_tin: context.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin,
          internal_id: doc[:codeNumber],
          uuid: accepted["uuid"],
          submission_uid: response["submissionUid"],
          status: "submitted",
          submitted_at: Time.current,
          raw_response: response
        )
        submission.save!
        { success: true, submission: submission }
      elsif rejected
        error_details = rejected.dig("error", "details") || []
        submission.assign_attributes(
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          status: "invalid",
          internal_id: doc[:codeNumber],
          raw_response: response,
          error_details: { rejected: rejected, messages: error_details.map { |e| e["message"] } }
        )
        submission.save!
        error_result("Adjustment rejected: #{error_details.map { |e| e["message"] }.join(", ")}")
      else
        error_result("Unexpected MyInvois response: #{response.inspect}")
      end
    end

    def skip(message)
      { success: false, skipped: true, message: message }
    end

    def error_result(message)
      { success: false, error: message }
    end
  end
end
