# frozen_string_literal: true

module EInvoice
  # The e-invoice state a guest can see, as a plain hash.
  #
  # The download URL comes from the caller, so the Guest Portal and the stay
  # page can each give their own route without this class knowing either.
  class GuestStatusPayload
    def initialize(booking:, download_url: nil)
      @booking = booking
      @download_url = download_url
    end

    def call
      if (submission = booking.latest_ready_guest_e_invoice_submission)
        payload("ready", ready_message(submission), submission, download_url)
      elsif (submission = booking.latest_pending_guest_e_invoice_submission)
        payload("processing", "We are preparing your e-invoice with LHDN now.", submission)
      elsif (submission = booking.latest_failed_guest_e_invoice_submission)
        payload("failed", failed_message(submission), submission)
      else
        payload("idle", "No guest e-invoice request has been submitted yet.", nil)
      end
    end

    private

    attr_reader :booking, :download_url

    def payload(status, message, submission, url = nil)
      {
        status: status,
        message: message,
        document_label: submission&.document_type_label,
        download_url: url
      }
    end

    def ready_message(submission)
      submission.adjustment? ? "Your updated e-invoice is ready." : "Your e-invoice is ready."
    end

    def failed_message(submission)
      submission.error_message.presence ||
        "We could not generate the e-invoice yet. Our hotel team can help retry it."
    end
  end
end
