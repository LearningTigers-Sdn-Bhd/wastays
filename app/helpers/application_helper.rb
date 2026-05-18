module ApplicationHelper
  def booking_status_class(status)
    case status
    when "confirmed" then "bg-green-100 text-green-800"
    when "checked_in" then "bg-blue-100 text-blue-800"
    when "completed" then "bg-emerald-100 text-emerald-800"
    when "cancelled" then "bg-red-100 text-red-800"
    when "no_show" then "bg-orange-100 text-orange-800"
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
    when "cancel", "rejected", "failed", "cancelled" then "bg-red-50 text-red-700 border border-red-100"
    when "pending", "requested" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
    else "bg-gray-50 text-gray-700 border border-gray-100"
    end
  end

  def complaint_status_class(status)
    case status
    when "resolved", "completed" then "bg-green-50 text-green-700 border border-green-100"
    when "failed", "cancelled" then "bg-red-50 text-red-700 border border-red-100"
    when "pending" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
    else "bg-gray-50 text-gray-700 border border-gray-100"
    end
  end

  def status_badge_class(status_class)
    status_class.gsub("bg-", "border-")
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

  def format_duration(seconds)
    return "N/A" if seconds.blank?

    days = (seconds / 86400).to_i
    hours = ((seconds % 86400) / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i

    parts = []
    parts << "#{days}d" if days > 0
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0 && days == 0 # Only show minutes if less than a day

    parts.any? ? parts.join(" ") : "< 1m"
  end

  def sanitize_href(url)
    return "#" if url.blank?
    return url if url.start_with?("http://", "https://")
    "#"
  end
end
