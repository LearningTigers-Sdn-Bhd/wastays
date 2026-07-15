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
  end
end
