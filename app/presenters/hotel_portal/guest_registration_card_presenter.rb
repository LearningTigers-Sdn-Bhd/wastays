# frozen_string_literal: true

module HotelPortal
  class GuestRegistrationCardPresenter
    attr_reader :card, :booking, :hotel

    def initialize(card, booking)
      @card = card
      @booking = booking
      @hotel = booking.hotel
    end

    def terms
      @terms ||= @card.signed? ? @card.terms_snapshot : @card.capture_terms_snapshot_preview
    end

    def primary_booking_guest
      @primary_booking_guest ||= @booking.booking_guests.find(&:primary?)
    end

    def guest_name
      primary_booking_guest&.name_snapshot.presence || @booking.guest_name
    end

    def guest_phone
      primary_booking_guest&.phone_snapshot.presence || @booking.guest_phone
    end

    def guest_email
      primary_booking_guest&.email_snapshot.presence || @booking.guest_email
    end

    def guest_country
      primary_booking_guest&.country_snapshot.presence || @booking.guest_country
    end

    def room_type_summary
      @booking.room_type_summary.presence || "To be assigned"
    end

    def currency
      @booking.currency.presence || @hotel.default_currency.presence || "MYR"
    end

    def format_money(amount)
      format("%<currency>s %<amount>.2f", currency: currency, amount: amount.to_d)
    end

    def folios_charges
      @folios_charges ||= @booking.booking_folios.sum { |f| f.total_charges.to_d + f.projected_forecasts.sum(:amount).to_d }
    end

    def total_charges
      folios_charges > 0 ? folios_charges : @booking.total_amount
    end

    def amount_paid
      @amount_paid ||= @booking.booking_folios.sum { |f| f.total_payments.to_d }
    end

    def due_amount
      total_charges - amount_paid
    end

    def guest_country_display
      guest_country.presence || "-"
    end

    def guest_identity
      primary_booking_guest&.government_id_snapshot.presence ||
        @booking.guest_government_id.presence ||
        "-"
    end

    def guest_count_display
      "#{booking.adults.to_i} adult(s), #{booking.children.to_i} child(ren)"
    end

    def room_price
      booking.booking_rooms.sum(:subtotal)
    end

    def room_price_display
      format_money(room_price)
    end

    def room_numbers_display
      booking.room_numbers.presence || "To be assigned"
    end

    def rate_type_display
      booking.booking_rooms.first&.rate_plan&.name || "Standard"
    end

    def note_templates
      @note_templates ||= hotel.guest_registration_note_templates.order(created_at: :desc)
    end

    def hotel_address_display
      [ hotel.city, hotel.country ].compact_blank.join(", ")
    end
  end
end
