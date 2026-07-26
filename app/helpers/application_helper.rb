module ApplicationHelper
  def toast_flash_messages(flash)
    messages = []
    toast_data = flash[:toast]

    if toast_data.present?
      toast_data = toast_data.with_indifferent_access if toast_data.respond_to?(:with_indifferent_access)
      if toast_data.is_a?(Hash) && toast_data[:message].present?
        messages << {
          message: toast_data[:message].to_s,
          options: { type: toast_data[:type].presence || "default", description: toast_data[:description].presence }.compact
        }
      end
    end

    flash.each do |key, value|
      next if key.to_sym == :toast || value.blank?

      messages << { message: value.to_s, options: { type: Toast.type_for_flash(key) } }
    end

    messages
  end

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

  # ViewComponent-backed replacement for `cached_icon`, in progress. Not called
  # from any view yet — migrate call sites to this one at a time, then retire
  # `cached_icon` once nothing references it. See AppIconComponent.
  def app_icon(name, **arguments)
    render(AppIconComponent.new(name, **arguments))
  end

  def booking_status_class(status)
    case status
    when "confirmed" then "bg-green-100 text-green-800"
    when "review_no_show" then "bg-amber-100 text-amber-800"
    when "checked_in" then "bg-blue-100 text-blue-800"
    when "completed" then "bg-emerald-100 text-emerald-800"
    when "cancelled" then "bg-red-100 text-red-800"
    when "voided" then "bg-red-100 text-red-800"
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

  def display_amount(amount, quote_currency:, display_currency:, hotel:)
    conversion = CurrencyConverter.convert(amount, from: quote_currency, to: display_currency)
    target_currency = conversion.present? ? display_currency : quote_currency
    value = conversion&.amount || amount

    CurrencyFormatter.format(value, currency: target_currency)
  end

  def pax_pricing_breakdown_items(item, hotel, display_currency)
    occ = item.occupancy_snapshot || {}
    adults = (occ["adults"] || occ[:adults] || 0).to_i
    children = (occ["children"] || occ[:children] || 0).to_i
    total_pax = adults + children

    quantity = item.respond_to?(:quantity) ? item.quantity : 1

    rate_plan_id = nil
    if item.nightly_rate_snapshot.present?
      first_rate_data = item.nightly_rate_snapshot.values.first
      rate_plan_id = first_rate_data["rate_plan_id"] if first_rate_data.is_a?(Hash)
    end
    rate_plan = RatePlan.find_by(id: rate_plan_id)
    return [] unless rate_plan

    child_multiplier = rate_plan.child_price_multiplier || 1.to_d

    # Sum up for the stay
    dates = item.nightly_rate_snapshot.keys.map { |d| Date.parse(d) }
    nights_count = dates.size
    return [] if nights_count.zero?

    total_adults_cost = 0.to_d
    total_children_cost = 0.to_d
    total_supplement = 0.to_d

    item.nightly_rate_snapshot.each do |date_str, snapshot|
      date = Date.parse(date_str)
      room_rate = RoomRate.find_by(room_type_id: item.room_type_id, rate_plan_id: rate_plan_id, date: date)
      base_price = room_rate&.price || item.room_type.base_price || 0.to_d

      total_adults_cost += adults * base_price
      total_children_cost += children * base_price * child_multiplier

      if total_pax == 1
        supplement = room_rate&.single_supplement || rate_plan.single_supplement || 0.to_d
        total_supplement += supplement
      end
    end

    lines = []
    quote_curr = item.respond_to?(:booking_quote) ? item.booking_quote&.currency : nil
    quote_curr ||= item.respond_to?(:booking) ? item.booking&.currency : nil
    quote_curr ||= hotel.default_currency || "MYR"

    if adults > 0
      avg_adult_rate = (total_adults_cost / (adults * nights_count)).round(2)
      formatted_rate = display_amount(avg_adult_rate, quote_currency: quote_curr, display_currency: display_currency, hotel: hotel)
      formatted_total = display_amount(total_adults_cost * quantity, quote_currency: quote_curr, display_currency: display_currency, hotel: hotel)
      lines << {
        label: "#{adults * quantity} Adult(s)",
        detail: "#{nights_count} night(s) @ #{formatted_rate}",
        amount: formatted_total
      }
    end

    if children > 0
      avg_child_rate = (total_children_cost / (children * nights_count)).round(2)
      formatted_rate = display_amount(avg_child_rate, quote_currency: quote_curr, display_currency: display_currency, hotel: hotel)
      formatted_total = display_amount(total_children_cost * quantity, quote_currency: quote_curr, display_currency: display_currency, hotel: hotel)
      lines << {
        label: "#{children * quantity} Child(ren)",
        detail: "#{nights_count} night(s) @ #{formatted_rate} (#{(child_multiplier * 100).to_i}%)",
        amount: formatted_total
      }
    end

    if total_supplement > 0
      formatted_total = display_amount(total_supplement * quantity, quote_currency: quote_curr, display_currency: display_currency, hotel: hotel)
      lines << {
        label: "Single Supplement",
        detail: "#{nights_count} night(s)",
        amount: formatted_total
      }
    end

    lines
  end
end
