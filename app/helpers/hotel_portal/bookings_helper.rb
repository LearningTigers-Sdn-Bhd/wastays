module HotelPortal::BookingsHelper
  def pre_checkin_display_status(booking)
    booking.pre_checkin_display_status
  end

  def pre_checkin_status_class(status)
    case status
    when "completed" then "bg-green-100 text-green-800"
    when "in_progress" then "bg-blue-100 text-blue-800"
    when "failed" then "bg-red-100 text-red-800"
    when "pending" then "bg-yellow-100 text-yellow-800"
    else "bg-gray-100 text-gray-800"
    end
  end
end
