module ApplicationHelper
  def cached_icon(name, library: RailsIcons.configuration.default_library, from: library, variant: nil, **arguments)
    @_cached_icons ||= {}
    key = [ name.to_s, library.to_s, from.to_s, variant&.to_s, arguments ]
    return @_cached_icons[key].dup.html_safe if @_cached_icons.key?(key)

    @_cached_icons[key] = begin
      icon(name, library: library, from: from, variant: variant, **arguments).to_s.freeze
    rescue StandardError => e
      Rails.logger.error("Icon not found: #{name} (#{e.message})")
      ""
    end
    @_cached_icons[key].dup.html_safe
  end

  def booking_status_class(status)
    case status
    when "confirmed" then "bg-green-100 text-green-800"
    when "review_no_show" then "bg-amber-100 text-amber-800"
    when "checked_in" then "bg-blue-100 text-blue-800"
    when "completed" then "bg-emerald-100 text-emerald-800"
    when "cancelled" then "bg-red-100 text-red-800"
    when "no_show" then "bg-orange-100 text-orange-800"
    when "pending" then "bg-yellow-100 text-yellow-800"
    else "bg-gray-100 text-gray-800"
    end
  end

  def guest_booking_status(booking)
    booking.status == "review_no_show" ? "confirmed" : booking.status
  end

  def refund_status_class(status)
    case status
    when "pending" then "bg-yellow-100 text-yellow-700"
    when "approved" then "bg-blue-100 text-blue-700"
    when "completed" then "bg-green-100 text-green-700"
    when "rejected" then "bg-red-100 text-red-700"
    else "bg-gray-100 text-gray-700"
    end
  end

  def guest_booking_badge_class(booking)
    status = guest_booking_status(booking)
    status == "confirmed" ? "bg-green-100 text-green-700" : "bg-neutral-100 text-neutral-600"
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

  def payout_status_class(status)
    case status
    when "paid" then "bg-emerald-50 text-emerald-700 border-emerald-200"
    when "processing" then "bg-amber-50 text-amber-700 border-amber-200"
    when "pending" then "bg-slate-50 text-slate-600 border-slate-200"
    else "bg-gray-50 text-gray-600 border-gray-200"
    end
  end

  def status_badge_class(status_class)
    status_class.gsub("bg-", "border-")
  end

  def format_date(date)
    return "" if date.blank?

    date.respond_to?(:strftime) ? date.strftime("%d %b %Y") : Date.parse(date.to_s).strftime("%d %b %Y")
  rescue ArgumentError, TypeError
    date.to_s
  end

  def status_badge_classes(tone, active: false)
    return "border-white/20 bg-white/15 text-white" if active

    case tone.to_s
    when "blue" then "border-blue-200 bg-blue-50 text-blue-700"
    when "emerald" then "border-emerald-200 bg-emerald-50 text-emerald-700"
    when "amber" then "border-amber-200 bg-amber-50 text-amber-700"
    when "orange" then "border-orange-200 bg-orange-50 text-orange-700"
    when "rose" then "border-rose-200 bg-rose-50 text-rose-700"
    else "border-slate-200 bg-slate-50 text-slate-600"
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

  def id_scanner_attached?(form, field)
    form.object.send(field).attached?
  end

  def id_scanner_preview_url(form, field)
    url_for(form.object.send(field))
  end

  def id_scanner_placeholder_icon(side)
    icon_name = side == :front ? "user" : "credit-card"
    cached_icon(icon_name, stroke_width: 1.5, class: "w-12 h-12")
  end

  def id_scanner_side_label(side)
    side == :front ? "Front Side" : "Back Side"
  end
end
