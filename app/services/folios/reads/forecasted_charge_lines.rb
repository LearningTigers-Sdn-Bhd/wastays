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
        if ota_financial_snapshot_available?(@booking)
          return [] if ota_financial_snapshot_for(@booking).reconciliation_status == "total_mismatch"

          ota_lines = ota_financial_component_lines(@booking).select { |line| stay_dates.include?(line[:stay_date]) }
          ota_lines + stay_dates.flat_map { |date| supplemental_pms_tax_lines(date) }
        else
          stay_dates.flat_map do |date|
            accommodation_lines(date) + tax_lines(date)
          end
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
            transaction_type: "charge",
            identity: room.id.to_s,
            amount: amount,
            description: "Room Charge - #{date}",
            transaction_code: transaction_codes.room_revenue,
            transaction_code_id: transaction_codes.room_revenue&.id
          }
        end
      end

      def supplemental_pms_tax_lines(date)
        postings = tax_postings_for(@booking, date).reject { |posting| posting["source"] == "ota_supplied" }
        tax_lines(date, postings: postings)
      end

      def tax_lines(date, postings: tax_postings_for(@booking, date))
        postings.each_with_index.filter_map do |tax_line, index|
          amount = tax_line_amount(tax_line)
          next if amount.zero?

          transaction_code = transaction_codes.for_tax_line(tax_line)

          {
            stay_date: date,
            charge_kind: "tax",
            category: "tax",
            transaction_type: "charge",
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
        booking_dates = Bookings::ScheduledStay.stay_dates(
          hotel: @booking.hotel,
          check_in: @booking.check_in,
          check_out: @booking.check_out
        )
        return booking_dates if @dates.blank?

        requested_dates = Array(@dates).flat_map { |value| value.is_a?(Range) ? value.to_a : value }.map(&:to_date)
        booking_dates & requested_dates
      end
    end
  end
end
