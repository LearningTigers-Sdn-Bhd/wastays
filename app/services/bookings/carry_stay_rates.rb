# frozen_string_literal: true

module Bookings
  # Reprices a date change at the price the stay is already sold at, instead of
  # today's room rates. A hand-set price (a manual override, a per-night charge
  # correction, an imported total) or an OTA price is a deal the hotel made with
  # this guest; moving or extending the stay must not quietly swap it for rack
  # rate, nor spread the old total across more nights.
  #
  # Nights that stay in the booking keep their recorded price. Added nights take
  # the price of the nearest retained night — the last night when check-out
  # moves later, the first when check-in moves earlier. A stay moved to entirely
  # new dates keeps its nightly prices in order.
  #
  # Returns a BuildFinancialSnapshot result, or nil when the stay is priced from
  # room rates and a normal reprice is correct.
  class CarryStayRates
    SOURCE = "carried_stay_rate"
    CARRIED_KEYS = %w[price posting_price currency rate_plan_id room_type_id].freeze

    def self.call(**attributes)
      new(**attributes).call
    end

    # Whether this booking's price is one the hotel agreed rather than rack rate.
    def self.agreed_price?(booking)
      booking.manual_rate_override.present? || booking.ota_booking?
    end

    def initialize(booking:, booking_room:, rate_plan:, previous_check_in:, previous_check_out:, check_in:, check_out:)
      @booking = booking
      @booking_room = booking_room
      @rate_plan = rate_plan
      @previous_dates = stay_dates(previous_check_in, previous_check_out)
      @dates = stay_dates(check_in, check_out)
      @check_in = check_in
      @check_out = check_out
    end

    def call
      return unless applies?

      previous = previous_prices
      return if previous.blank?

      BuildFinancialSnapshot.new(
        hotel: @booking.hotel,
        booking: @booking,
        check_in: @check_in,
        check_out: @check_out,
        guest_country: @booking.guest_country,
        room_type: @booking_room.room_type,
        rate_plan: @rate_plan,
        room_items: [ { quantity: 1, nightly_rate_snapshot: carried_snapshot(previous) } ]
      ).call
    end

    private

    def applies?
      return false if @booking_room.blank? || @dates.empty? || @previous_dates.empty?
      # Day-use and overnight stays are priced by different plans; let the
      # normal reprice raise its error rather than carry a price across.
      return false if @rate_plan && (@check_in.to_date == @check_out.to_date) != @rate_plan.day_use?

      self.class.agreed_price?(@booking)
    end

    # The recorded price for each night of the current stay. A legacy override
    # booking without a nightly snapshot is split evenly, as it was billed.
    def previous_prices
      snapshot = @booking_room.nightly_rate_snapshot.to_h
      prices = @previous_dates.to_h { |date| [ date, snapshot[date.iso8601] ] }
      return prices if prices.values.all? { |entry| entry.is_a?(Hash) && entry["price"].present? }
      return if @booking.manual_rate_override.blank?

      even_split(@booking.manual_rate_override.to_d)
    end

    def even_split(total)
      nights = @previous_dates.size
      per_night = (total / nights).round(2)
      @previous_dates.each_with_index.to_h do |date, index|
        price = index == nights - 1 ? total - (per_night * (nights - 1)) : per_night
        [ date, {
          "date" => date.iso8601, "price" => price.to_s("F"),
          "currency" => @booking.currency.presence || @booking.hotel.default_currency.presence || "MYR",
          "rate_plan_id" => @rate_plan&.id, "room_type_id" => @booking_room.room_type_id, "source" => "manual_override"
        }.compact ]
      end
    end

    def carried_snapshot(previous)
      retained = @dates & previous.keys
      @dates.each_with_index.to_h do |date, index|
        next [ date.iso8601, previous.fetch(date) ] if previous.key?(date)

        from = if retained.empty?
          previous.keys[[ index, previous.size - 1 ].min]
        else
          date < retained.first ? retained.first : retained.last
        end
        [ date.iso8601, carried_entry(previous.fetch(from), date, from) ]
      end
    end

    def carried_entry(entry, date, from)
      entry.slice(*CARRIED_KEYS).merge(
        "date" => date.iso8601, "source" => SOURCE, "carried_from" => from.iso8601
      )
    end

    def stay_dates(check_in, check_out)
      ScheduledStay.billable_dates(check_in.to_date, check_out.to_date)
    end
  end
end
