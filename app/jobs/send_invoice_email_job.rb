class SendInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    BookingMailer.invoice(booking).deliver_now
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError => e
    Rails.logger.warn("SendInvoiceEmailJob skipped booking #{booking_id}: #{e.message}")
  end
end
