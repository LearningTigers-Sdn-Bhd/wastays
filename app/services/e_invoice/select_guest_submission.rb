# frozen_string_literal: true

module EInvoice
  # Picks the e-invoice submission to serve a guest. A named submission wins, so
  # a guest can open an older document. Otherwise the latest ready one wins.
  class SelectGuestSubmission
    def initialize(booking:, submission_id: nil)
      @booking = booking
      @submission_id = submission_id
    end

    def call
      return booking.latest_ready_guest_e_invoice_submission if submission_id.blank?

      booking.e_invoice_submissions.guest_facing.valid.find_by(id: submission_id)
    end

    private

    attr_reader :booking, :submission_id
  end
end
