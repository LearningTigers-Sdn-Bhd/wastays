# frozen_string_literal: true

module Folios
  class ForecastedChargeLines
    include NightlyChargeCalculation

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
          transaction_code: room_transaction_code,
          transaction_code_id: room_transaction_code&.id
        }
      end
    end

    def tax_lines(date)
      tax_postings_for(@booking, date).each_with_index.filter_map do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        transaction_code = transaction_code_for_tax_line(tax_line)

        {
          stay_date: date,
          charge_kind: "tax",
          category: "tax",
          identity: tax_line_identity(tax_line, index),
          amount: amount,
          description: "Tax: #{tax_line_name(tax_line)} - #{date}",
          transaction_code: transaction_code,
          transaction_code_id: transaction_code&.id,
          fallback_transaction_code: source_transaction_code(tax_line),
          fallback_transaction_code_id: source_transaction_code(tax_line)&.id,
          tax_line: tax_line
        }
      end
    end

    def room_transaction_code
      @room_transaction_code ||= @booking.hotel.transaction_codes.find_by(system_key: "room_revenue")
    end

    def transaction_code_for_tax_line(tax_line)
      id = tax_line["transaction_code_id"].presence || tax_line[:transaction_code_id].presence
      return @booking.hotel.transaction_codes.find_by(id: id) if id.present?

      case tax_line["type"].presence || tax_line[:type].presence
      when "sst" then @booking.hotel.transaction_codes.find_by(system_key: "sst_tax")
      when "tourism_tax" then @booking.hotel.transaction_codes.find_by(system_key: "tourism_tax")
      end
    end

    def source_transaction_code(tax_line)
      id = tax_line["source_transaction_code_id"].presence || tax_line[:source_transaction_code_id].presence
      return @booking.hotel.transaction_codes.find_by(id: id) if id.present?

      nil
    end

    def stay_dates
      booking_dates = (@booking.check_in.to_date...@booking.check_out.to_date).to_a
      return booking_dates if @dates.blank?

      requested_dates = Array(@dates).flat_map { |value| value.is_a?(Range) ? value.to_a : value }.map(&:to_date)
      booking_dates & requested_dates
    end
  end
end
