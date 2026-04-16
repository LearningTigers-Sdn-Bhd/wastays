module ApplicationHelper
  def booking_status_class(status)
    case status
    when "confirmed" then "bg-green-100 text-green-800"
    when "checked_in" then "bg-blue-100 text-blue-800"
    when "completed" then "bg-gray-100 text-gray-800"
    when "cancelled" then "bg-red-100 text-red-800"
    when "pending" then "bg-yellow-100 text-yellow-800"
    else "bg-gray-100 text-gray-800"
    end
  end

  def payment_status_class(status)
    case status
    when "captured" then "bg-green-100 text-green-800"
    when "pending" then "bg-yellow-100 text-yellow-800"
    when "failed" then "bg-red-100 text-red-800"
    else "bg-gray-100 text-gray-800"
    end
  end

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

  def housekeeping_status_class(status)
    case status
    when "completed", "resolved" then "bg-green-50 text-green-700 border border-green-100"
    when "cancel", "rejected" then "bg-red-50 text-red-700 border border-red-100"
    when "pending", "requested" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
    else "bg-gray-50 text-gray-700 border border-gray-100"
    end
  end

  def complaint_status_class(status)
    case status
    when "resolved", "completed" then "bg-green-50 text-green-700 border border-green-100"
    when "in_progress" then "bg-blue-50 text-blue-700 border border-blue-100"
    when "failed" then "bg-red-50 text-red-700 border border-red-100"
    when "pending" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
    else "bg-gray-50 text-gray-700 border border-gray-100"
    end
  end

  def display_housekeeping_date(value)
    return "Not provided" if value.blank?

    return value.strftime("%d %b %Y") if value.respond_to?(:strftime)

    parsed_value = Time.zone.parse(value.to_s)
    parsed_value ? parsed_value.strftime("%d %b %Y") : value.to_s
  rescue ArgumentError, TypeError
    value.to_s
  end

  def display_housekeeping_datetime(value)
    return "Not provided" if value.blank?

    return value.strftime("%d %b %Y, %I:%M %p") if value.respond_to?(:strftime)

    parsed_value = Time.zone.parse(value.to_s)
    parsed_value ? parsed_value.strftime("%d %b %Y, %I:%M %p") : value.to_s
  rescue ArgumentError, TypeError
    value.to_s
  end
end
