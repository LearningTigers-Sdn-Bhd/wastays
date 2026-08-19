# frozen_string_literal: true

module HotelPortal
  class GuestRegistrationCardPresenter
    attr_reader :card, :booking, :hotel, :selected_booking_guest

    def initialize(card, booking, booking_guest_id: nil)
      @card = card
      @booking = booking
      @hotel = booking.hotel
      @selected_booking_guest = find_booking_guest(booking_guest_id)
    end

    def terms
      @terms ||= @card.signed? ? @card.terms_snapshot : @card.capture_terms_snapshot_preview
    end

    # The hotel's own fixed wording, set once in Settings rather than picked or
    # typed per booking. Snapshotted the same way the cancellation policy is, so
    # a later edit in Settings never changes what an already-signed guest agreed to.
    def terms_and_conditions
      terms&.dig("terms_and_conditions")
    end

    # Tier table first, the hotel's own wording beneath it. Cards signed before the
    # policy became structured still carry prose, and fall back to it.
    def cancellation_summary
      @cancellation_summary ||= Cancellations::PolicySummary.call(
        snapshot_data: terms&.dig("cancellation_policy_data"),
        legacy_text: terms&.dig("cancellation_policy")
      )
    end

    def primary_booking_guest
      @primary_booking_guest ||= @booking.booking_guests.find(&:primary?)
    end

    def active_booking_guest
      @selected_booking_guest || primary_booking_guest
    end

    def guest_name
      active_booking_guest&.name_snapshot.presence || @booking.guest_name
    end

    def guest_phone
      active_booking_guest&.phone_snapshot.presence || @booking.guest_phone
    end

    def guest_email
      active_booking_guest&.email_snapshot.presence || @booking.guest_email
    end

    def guest_country
      active_booking_guest&.country_snapshot.presence || @booking.guest_country
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
      active_booking_guest&.government_id_snapshot.presence ||
        (active_booking_guest&.primary? ? @booking.guest_government_id.presence : nil) ||
        "-"
    end

    def guest_count_display
      adults = booking.adults.to_i
      children = booking.children.to_i
      "#{adults} #{"adult".pluralize(adults)}, #{children} #{"child".pluralize(children)}"
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

    def boat_transfer?
      active_booking_guest&.boat_in? || active_booking_guest&.boat_out?
    end

    def boat_in_display
      format_boat_time(active_booking_guest&.boat_in_at)
    end

    def boat_out_display
      format_boat_time(active_booking_guest&.boat_out_at)
    end

    def check_in_display
      format_stay_datetime(booking.check_in.to_date, terms&.dig("check_in_time"))
    end

    def check_out_display
      format_stay_datetime(booking.check_out.to_date, terms&.dig("check_out_time"))
    end

    private

    def find_booking_guest(booking_guest_id)
      return nil if booking_guest_id.blank?

      @booking.booking_guests.find { |bg| bg.id.to_s == booking_guest_id.to_s }
    end

    def format_boat_time(time)
      return "-" if time.blank?

      time.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %I:%M %p")
    end

    def format_stay_datetime(date, time)
      formatted_date = date.strftime("%d %b %Y")
      formatted_time = format_time_of_day(time)
      formatted_time.present? ? "#{formatted_date}, #{formatted_time}" : formatted_date
    end

    TWENTY_FOUR_HOUR_TIME = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

    def format_time_of_day(time)
      return nil if time.blank?
      return time unless TWENTY_FOUR_HOUR_TIME.match?(time)

      Time.strptime(time, "%H:%M").strftime("%I:%M %p")
    end
  end
end
