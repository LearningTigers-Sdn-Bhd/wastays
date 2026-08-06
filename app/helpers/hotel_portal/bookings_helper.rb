module HotelPortal::BookingsHelper
  STATUS_ICONS = {
    "pending" => "clock",
    "confirmed" => "circle-check",
    "no_show_detected" => "triangle-alert",
    "checked_in" => "log-in",
    "completed" => "check-check",
    "cancelled" => "circle-x",
    "voided" => "circle-slash",
    "no_show" => "user-x",
    "due_out_detected" => "triangle-alert",
    "checkout_required" => "log-out",
    "overbooked" => "octagon-alert",
    "not_ready" => "ban",
    "available" => "circle-check"
  }.freeze

  def booking_status_icon(status)
    STATUS_ICONS.fetch(status.to_s, "circle")
  end

  def hotel_payment_display_status(status)
    status.to_s == "refunded" ? "cancelled" : status
  end

  def hotel_payment_status_class(status)
    display_status = hotel_payment_display_status(status)
    return booking_status_class("cancelled") if display_status.to_s == "cancelled"

    payment_status_class(display_status)
  end

  def folio_transaction_amount_label(transaction, currency: nil)
    amount = transaction.amount.to_d
    signed_amount = case transaction.transaction_type
    when "charge" then amount
    when "payment" then -amount
    else amount
    end

    sign = signed_amount.negative? ? "-" : "+"
    currency_label = currency ? currency : " MYR"
    "#{sign}#{currency_label} #{number_with_precision(signed_amount.abs, precision: 2, delimiter: ",")}"
  end

  def folio_transaction_amount_class(transaction)
    amount = transaction.amount.to_d
    balance_effect = transaction.payment? ? -amount : amount

    balance_effect.negative? ? "text-emerald-600" : "text-foreground"
  end

  def format_room_card_stay_dates(check_in, check_out)
    "#{check_in.strftime('%b %-d')} → #{check_out.strftime('%b %-d')}"
  end

  # Boat slots are stored on the primary guest. Which one a list cares about
  # depends on where the guest is in their stay: arrivals want the boat landing,
  # everyone from check-in onward the one leaving.
  # The hotel is passed in rather than read off the booking: these render one
  # row per booking, and booking.hotel is not eager-loaded by the list queries.
  def booking_boat_time(booking, kind, hotel)
    primary = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
    time = kind == :in ? primary&.boat_in_at : primary&.boat_out_at
    return if time.blank?

    local = time.in_time_zone(hotel.hotel_time_zone)
    { time: local.strftime("%H:%M"), date: local.strftime("%d %b") }
  end

  def show_boat_times?(hotel)
    hotel.allow_boat_information?
  end

  def guest_display_field(val, default = "—")
    val.presence || default
  end

  def guest_document_type_display(doc_type)
    doc_type.presence&.to_s&.upcase || "IC/PASSPORT"
  end

  def booking_source_select_options(selected)
    grouped_options_for_select(
      {
        "Manual / Direct" => HotelPortal::BookingSourcePresenter.manual_options,
        "Online Travel Agency" => HotelPortal::BookingSourcePresenter.ota_options,
        "Other Channel" => HotelPortal::BookingSourcePresenter.other_channel_options
      },
      selected
    )
  end

  # Flat [label, value] pairs for PanelsUI::SelectMenu (choices:), which has no
  # optgroup support — grouping is only available via booking_source_select_options
  # for plain f.select usage.
  def booking_source_choices
    HotelPortal::BookingSourcePresenter.manual_options +
      HotelPortal::BookingSourcePresenter.ota_options +
      HotelPortal::BookingSourcePresenter.other_channel_options
  end
end
