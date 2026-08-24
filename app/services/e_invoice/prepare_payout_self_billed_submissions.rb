# frozen_string_literal: true

module EInvoice
  class PreparePayoutSelfBilledSubmissions
    def self.call(payout_batch)
      new(payout_batch).call
    end

    def initialize(payout_batch)
      @payout_batch = payout_batch
      @hotel = payout_batch.hotel
    end

    def call
      return [] unless @hotel.e_invoice_setting&.enabled?
      return [] unless @hotel.e_invoice_setting&.supplier_profile_ready?

      @payout_batch.bookings.where(fund_collector: "wastays").map do |booking|
        submission = booking.e_invoice_submissions.find_or_initialize_by(
          document_scenario: "payout_self_billed_invoice",
          payout_batch: @payout_batch
        )

        next submission if submission.persisted? && (submission.validated? || submission.submitted? || submission.pending?)

        submission.assign_attributes(
          hotel: @hotel,
          booking: booking,
          payout_batch: @payout_batch,
          document_type: "11",
          submission_mode: "taxpayer",
          fund_collector: "wastays",
          supplier_name: @hotel.name,
          supplier_tin: @hotel.e_invoice_setting.hotel_tin,
          represented_taxpayer_tin: nil,
          status: "pending",
          uuid: nil,
          long_id: nil,
          submission_uid: nil,
          submitted_at: nil,
          validated_at: nil,
          cancelled_at: nil,
          raw_response: {},
          error_details: {}
        )
        submission.save!
        EInvoice::SubmitJob.perform_later(submission.id)
        submission
      end
    end
  end
end
