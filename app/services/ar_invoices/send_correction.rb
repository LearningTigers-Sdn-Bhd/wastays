# frozen_string_literal: true

module ArInvoices
  class SendCorrection
    Result = ApplicationResult.define

    def self.call(correction:)
      correction.with_lock do
        return Result.failure("Wait for the correction documents to finish processing.") unless correction.completed?
        return Result.failure("A newer correction has replaced these documents.") if correction.replacement_receivable&.void?
        return Result.failure("Save a company contact email before sending.") if correction.original_receivable.hotel_corporate_account.effective_contact_email.blank?
        correction.update!(send_documents: true)
        delivery = NotificationDelivery.find_by(idempotency_key: "ar_correction:#{correction.id}")
        if delivery&.status.in?(%w[failed skipped])
          delivery.update!(status: "pending", error_message: nil,
            payload: delivery.payload.merge("recipient_email" => correction.original_receivable.hotel_corporate_account.effective_contact_email))
          Notifications::DeliverJob.perform_later(delivery.id)
        elsif delivery.nil?
          Notifications::ArCorrectionDelivery.queue!(correction: correction)
        end
      end
      Result.success
    end
  end
end
