# frozen_string_literal: true

module ChannelManagers
  module Financials
    class ComparePmsRate
      Result = Data.define(:expected_amount, :variance_amount, :variance_percentage, :reason, :room_nights)

      def self.call(bookings:, accommodation_amount:)
        new(bookings:, accommodation_amount:).call
      end

      def initialize(bookings:, accommodation_amount:)
        @bookings, @accommodation_amount = bookings, accommodation_amount.to_d
      end

      def call
        expected = 0.to_d
        room_nights = 0
        @bookings.each do |booking|
          booking.booking_rooms.each do |room|
            (booking.check_in.to_date...booking.check_out.to_date).each do |date|
              room_nights += 1
              result = Rates::ResolveEffectiveNightlyPrice.call(
                room_type: room.room_type, rate_plan: room.rate_plan || room.room_type.standard_rate_plan,
                date: date, currency: booking.currency, adults: occupancy(room, "adults", booking.adults),
                children: occupancy(room, "children", 0)
              )
              return Result.new(expected_amount: nil, variance_amount: nil, variance_percentage: nil,
                reason: nil, room_nights:) if result.amount.nil?
              expected += result.amount.to_d
            end
          end
        end
        expected = expected.round(2)
        variance = (@accommodation_amount - expected).round(2)
        percentage = expected.zero? ? 0.to_d : (variance.abs * 100 / expected).round(6)
        Result.new(expected_amount: expected, variance_amount: variance, variance_percentage: percentage,
          reason: variance.zero? ? nil : "fx_round_trip", room_nights:)
      end

      private

      def occupancy(room, key, fallback)
        room.occupancy_snapshot.to_h[key].presence || fallback
      end
    end
  end
end
