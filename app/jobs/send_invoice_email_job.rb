class SendInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    result = FolioInvoicePackages::QueueDeliveries.call(
      hotel: booking.hotel,
      bookings: [ booking ],
      anchor_booking: booking,
      source: "automatic_checkout"
    )
    if result.groups.empty?
      Rails.logger.warn("SendInvoiceEmailJob skipped booking #{booking_id}: no eligible finalized invoices")
      return
    end

    result.deliveries.select { |delivery| delivery.status == "pending" }.each do |delivery|
      Notifications::DeliverJob.perform_now(delivery.id)
    end
  rescue FolioInvoicePackages::UnavailableError => e
    Rails.logger.warn("SendInvoiceEmailJob skipped booking #{booking_id}: #{e.message}")
  end
end
