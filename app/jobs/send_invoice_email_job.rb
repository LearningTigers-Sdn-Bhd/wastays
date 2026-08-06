# Compatibility bridge for invoice jobs queued before Notifications::InvoiceDelivery.
# Remove after one release, once the old queue has drained.
class SendInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    result = Notifications::InvoiceDelivery.queue(
      hotel: booking.hotel,
      bookings: [ booking ],
      anchor_booking: booking,
      source: "automatic_checkout"
    )
    if result.groups.empty?
      Rails.logger.warn("SendInvoiceEmailJob skipped booking #{booking_id}: no eligible finalized invoices")
    end
  rescue Notifications::InvoiceDelivery::UnavailableError => e
    Rails.logger.warn("SendInvoiceEmailJob skipped booking #{booking_id}: #{e.message}")
  end
end
