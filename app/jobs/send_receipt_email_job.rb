class SendReceiptEmailJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking
    return if booking.guest_email.blank?

    BookingMailer.receipt(booking).deliver_now
  end
end
