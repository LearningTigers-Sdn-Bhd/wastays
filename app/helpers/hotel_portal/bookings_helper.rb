module HotelPortal::BookingsHelper
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
    "#{sign}#{currency_label} #{number_with_precision(signed_amount.abs, precision: 2)}"
  end

  def folio_transaction_amount_class(transaction)
    amount = transaction.amount.to_d
    balance_effect = transaction.payment? ? -amount : amount

    balance_effect.negative? ? "text-emerald-600" : "text-slate-900"
  end

  def format_room_card_stay_dates(check_in, check_out)
    "#{check_in.strftime('%b %-d')} → #{check_out.strftime('%b %-d')}"
  end

  def room_card_boat_time_details(booking, user = nil)
    primary_bg = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
    return nil if primary_bg.nil?

    timezone = user&.time_zone || booking.hotel.hotel_time_zone
    checked_in_states = %w[checked_in review_due_out checkout_required completed]

    if checked_in_states.include?(booking.status)
      if primary_bg.boat_out_at.present?
        {
          type: :departure,
          label: "Boat-out",
          time_str: primary_bg.boat_out_at.in_time_zone(timezone).strftime("%H:%M"),
          class: "text-purple-600",
          title: "Boat-out Time"
        }
      end
    else
      if primary_bg.boat_in_at.present?
        {
          type: :arrival,
          label: "Boat-in",
          time_str: primary_bg.boat_in_at.in_time_zone(timezone).strftime("%H:%M"),
          class: "text-blue-600",
          title: "Boat-in Time"
        }
      end
    end
  end

  def format_booking_guest_boat_time(time, timezone)
    return "—" if time.blank?

    time.in_time_zone(timezone).strftime("%d %b %Y, %I:%M %p")
  end
end
