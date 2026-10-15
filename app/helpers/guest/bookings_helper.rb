# frozen_string_literal: true

# Builds the GuestUI booking pieces from a booking, so every portal page shows
# a stay, its status, and its numbers the same way.
module Guest::BookingsHelper
  def guest_booking_badge(booking)
    GuestUI::StatusBadge.new(**Guest::StatusBadges.booking(booking.status).to_h)
  end

  def guest_refund_badge(refund_request)
    GuestUI::StatusBadge.new(**Guest::StatusBadges.refund(refund_request.status).to_h)
  end

  # "12 Oct – 15 Oct 2026", as the guest portal lists a stay.
  def guest_stay_dates(booking)
    "#{booking.check_in.strftime('%d %b')} – #{booking.check_out.strftime('%d %b %Y')}"
  end

  # "3 nights · 2 adults, 1 child"
  def guest_stay_detail(booking)
    party = pluralize(booking.adults, "adult")
    party += ", #{pluralize(booking.children, 'child', plural: 'children')}" if booking.children.to_i.positive?
    "#{pluralize(booking.duration_in_nights, 'night')} · #{party}"
  end

  def guest_stay_summary(booking, eyebrow:, badge: guest_booking_badge(booking), heading_level: 2)
    GuestUI::StaySummary.new(
      eyebrow:, badge:, heading_level:,
      property: booking.hotel.name,
      location: [ booking.hotel.city, booking.hotel.country ].compact_blank.join(", "),
      dates: guest_stay_dates(booking),
      detail: guest_stay_detail(booking),
      reference: booking.formatted_reservation_number,
      code: booking.confirmation_token.to_s.upcase
    )
  end

  # The money on a card: what the guest has paid, and what is left. A
  # cancelled stay shows no outstanding amount -- whatever is left there is a
  # refund question, and the Refunds page answers it.
  def guest_booking_card(booking)
    balance = Bookings::GuestBalance.new(booking:).call
    due = [ balance.due, 0 ].max
    closed = Guest::StatusBadges.booking_group(booking.status) == "cancelled"

    GuestUI::BookingCard.new(
      href: guest_booking_path(booking),
      property: booking.hotel.name,
      badge: guest_booking_badge(booking),
      dates: guest_stay_dates(booking),
      detail: guest_stay_detail(booking),
      reference: booking.formatted_reservation_number,
      code: booking.confirmation_token.to_s.upcase,
      paid: guest_money(balance.paid, booking),
      outstanding: (guest_money(due, booking) unless closed),
      owing: due.positive?
    )
  end

  def guest_money(amount, booking)
    number_to_currency(amount, unit: "#{booking.currency} ")
  end
end
