# frozen_string_literal: true

module Folios
  module Reads
    class ForecastedChargeLines
      include Charges::NightlyChargeCalculation

      def self.call(booking:, dates: nil)
        new(booking:, dates:).call
      end

      def initialize(booking:, dates: nil)
        @booking = booking
        @dates = dates
      end

      def call
        stay_dates.flat_map do |date|
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
            category: "accommodation",
            identity: room.id.to_s,
            amount: amount,
            description: "Room Charge - #{date}",
            transaction_code: transaction_codes.room_revenue,
            transaction_code_id: transaction_codes.room_revenue&.id
          }
        end
      end

      def tax_lines(date)
        tax_postings_for(@booking, date).each_with_index.filter_map do |tax_line, index|
          amount = tax_line_amount(tax_line)
          next if amount.zero?

          transaction_code = transaction_codes.for_tax_line(tax_line)

          {
            stay_date: date,
            charge_kind: "tax",
            category: "tax",
            identity: tax_line_identity(tax_line, index),
            amount: amount,
            description: "Tax: #{tax_line_name(tax_line)} - #{date}",
            transaction_code: transaction_code,
            transaction_code_id: transaction_code&.id,
            fallback_transaction_code: transaction_codes.source_for_tax_line(tax_line),
            fallback_transaction_code_id: transaction_codes.source_for_tax_line(tax_line)&.id,
            tax_line: tax_line
          }
        end
      end

      def transaction_codes
        @transaction_codes ||= TransactionCodes::Resolver.for(@booking.hotel)
      end

      def stay_dates
        booking_dates = (@booking.check_in.to_date...@booking.check_out.to_date).to_a
        return booking_dates if @dates.blank?

        requested_dates = Array(@dates).flat_map { |value| value.is_a?(Range) ? value.to_a : value }.map(&:to_date)
        booking_dates & requested_dates
      end
    end
  end
end
