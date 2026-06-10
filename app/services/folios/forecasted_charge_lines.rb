# frozen_string_literal: true

module Folios
  class ForecastedChargeLines
    include NightlyChargeCalculation

    def self.call(booking:)
      new(booking:).call
    end

    def initialize(booking:)
      @booking = booking
    end

    def call
      (@booking.check_in.to_date...@booking.check_out.to_date).flat_map do |date|
        accommodation_lines(date) + tax_lines(date)
      end
    end

    private

    def accommodation_lines(date)
      @booking.booking_rooms.filter_map do |room|
        amount = nightly_room_amount(room, date)
        next if amount.zero?

        {
          stay_date: date,
          charge_kind: "accommodation",
          identity: room.id.to_s,
          amount: amount,
          description: "Room Charge - #{date}"
        }
      end
    end

    def tax_lines(date)
      tax_postings_for(@booking, date).each_with_index.filter_map do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        {
          stay_date: date,
          charge_kind: "tax",
          identity: tax_line_identity(tax_line, index),
          amount: amount,
          description: "Tax: #{tax_line_name(tax_line)} - #{date}"
        }
      end
    end
  end
end
