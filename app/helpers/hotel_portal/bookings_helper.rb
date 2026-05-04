module HotelPortal::BookingsHelper
  def hotel_payment_display_status(status)
    status.to_s == "refunded" ? "cancelled" : status
  end

  def hotel_payment_status_class(status)
    display_status = hotel_payment_display_status(status)
    return booking_status_class("cancelled") if display_status.to_s == "cancelled"

    payment_status_class(display_status)
  end
end
