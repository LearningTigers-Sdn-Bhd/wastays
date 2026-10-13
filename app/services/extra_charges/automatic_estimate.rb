# frozen_string_literal: true

module ExtraCharges
  # What the hotel's auto-apply extra charges will come to on one room, before
  # the booking exists -- so whoever is about to book (an agent pricing a
  # package, say) sees the whole cost up front.
  #
  # It follows ForecastQuote, which schedules them once the booking is made:
  # the same dates, the same units and each date's tax rounded on its own, so
  # the estimate and the folio agree to the cent. Taxes are the charge code's
  # defaults; a booking has no tax overrides of its own yet.
  class AutomaticEstimate
    Line = Data.define(:extra_charge, :amount) do
      def name = extra_charge.name
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, check_in:, check_out:, adults:, children:)
      @hotel = hotel
      @check_in = check_in
      @check_out = check_out
      @adults = adults
      @children = children
    end

    def call
      return [] if dates.empty?

      extra_charges.map { |extra_charge| Line.new(extra_charge:, amount: amount_for(extra_charge)) }
    end

    private

    def extra_charges
      @hotel.hotel_extra_charges.auto_applied.active.ordered
        .includes(transaction_code: { transaction_code_taxes: :hotel_tax })
    end

    def dates
      @dates ||= Bookings::ScheduledStay.stay_dates(hotel: @hotel, check_in: @check_in, check_out: @check_out)
        .select { |date| date >= @hotel.current_business_date }
    end

    def amount_for(extra_charge)
      base = money(extra_charge.rate_value.to_d * extra_charge.units_for(rooms: 1, adults: @adults, children: @children))
      taxes = extra_charge.transaction_code.transaction_code_taxes.select(&:enabled_for_posting?)
      tax = taxes.sum { |rule| money(rule.compute(base)) }
      money((base + tax) * (extra_charge.nightly? ? dates.size : 1))
    end

    def money(value) = value.to_d.round(2)
  end
end
