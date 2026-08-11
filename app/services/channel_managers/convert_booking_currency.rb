# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class ConvertBookingCurrency
    def initialize(booking_data:)
      @data = booking_data
      @hotel = booking_data[:hotel]
    end

    def call
      source_currency = CurrencyCatalog.normalize(@data[:currency], fallback: @hotel.default_currency)
      target_currency = CurrencyCatalog.normalize(@hotel.default_currency, fallback: source_currency)
      # Keep persisted domain records (hotel, room types and rate plans) intact.
      # Only the top-level payload and mutable room hashes need copying.
      converted_data = @data.dup

      if source_currency == target_currency
        converted_data[:currency] = target_currency
        return success(converted_data)
      end

      unit_conversion = CurrencyConverter.convert(1, from: source_currency, to: target_currency, hotel: @hotel)
      return failure("Missing exchange rate from #{source_currency} to #{target_currency}") unless unit_conversion

      source_total = @data[:total_amount].to_d
      converted_total = convert_amount(source_total, unit_conversion.rate, target_currency)
      converted_rooms = Array(@data[:rooms]).map do |room|
        room.merge(amount: convert_amount(room[:amount], unit_conversion.rate, target_currency))
      end

      converted_data[:currency] = target_currency
      converted_data[:total_amount] = converted_total
      converted_data[:rooms] = reconcile_rooms(converted_rooms, source_total, converted_total, target_currency)
      converted_data[:currency_conversion] = {
        "source_currency" => source_currency,
        "target_currency" => target_currency,
        "rate" => decimal_string(unit_conversion.rate),
        "source_total_amount" => decimal_string(source_total.round(2)),
        "converted_total_amount" => decimal_string(converted_total),
        "source" => unit_conversion.source
      }

      success(converted_data)
    end

    private

    # Rounding each room independently can drift a cent or two away from the
    # converted total. When the source rooms added up to the source total, absorb
    # that drift into the last room so the booking still balances.
    def reconcile_rooms(converted_rooms, source_total, converted_total, currency)
      return converted_rooms if converted_rooms.empty?

      precision = CurrencyCatalog.precision_for(currency)
      source_precision = CurrencyCatalog.precision_for(@data[:currency])
      source_rooms_total = Array(@data[:rooms]).sum { |room| room[:amount].to_d }
      return converted_rooms unless source_rooms_total.round(source_precision) == source_total.round(source_precision)

      drift = converted_total - converted_rooms.sum { |room| room[:amount].to_d }
      return converted_rooms if drift.zero?

      last_room = converted_rooms.last
      converted_rooms[0..-2] + [ last_room.merge(amount: (last_room[:amount].to_d + drift).round(precision)) ]
    end

    def convert_amount(amount, rate, currency)
      (amount.to_d * rate.to_d).round(CurrencyCatalog.precision_for(currency))
    end

    def decimal_string(value)
      value.to_d.to_s("F")
    end

    def success(booking_data)
      OpenStruct.new(success?: true, booking_data: booking_data)
    end

    def failure(message)
      OpenStruct.new(success?: false, booking_data: @data, message: message)
    end
  end
end
