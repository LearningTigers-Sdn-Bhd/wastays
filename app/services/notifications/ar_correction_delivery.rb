# frozen_string_literal: true

module Notifications
  class ArCorrectionDelivery
    def self.queue!(correction:)
      return unless correction.send_documents? && correction.completed?

      relationship = correction.original_receivable.hotel_corporate_account
      email = relationship.effective_contact_email
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: "ar_correction:#{correction.id}")
      return delivery if delivery.persisted?

      delivery.assign_attributes(hotel: correction.hotel, booking: correction.booking_folio.booking,
        notification_type: "ar_invoice_correction", channel: "email", trigger_event: "ar_invoice_corrected",
        status: email.present? ? "pending" : "skipped",
        error_message: ("Company contact email is missing." if email.blank?),
        payload: { correction_id: correction.id, recipient_email: email,
          payer_name: correction.original_snapshot.dig("payer", "name"), hotel_name: correction.hotel.name })
      delivery.save!
      DeliverJob.perform_later(delivery.id) if email.present?
      delivery
    end
  end
end
