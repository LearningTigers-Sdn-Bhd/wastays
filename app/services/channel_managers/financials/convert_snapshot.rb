# frozen_string_literal: true

module ChannelManagers
  module Financials
    class ConvertSnapshot
      Result = Data.define(:payload, :rate, :source, :rounding_amount)

      def self.call(financials:, target_currency:, hotel:)
        new(financials:, target_currency:, hotel:).call
      end

      def initialize(financials:, target_currency:, hotel:)
        @financials = financials.deep_dup
        @source_currency = CurrencyCatalog.normalize(@financials[:currency], fallback: nil)
        @target_currency = CurrencyCatalog.normalize(target_currency, fallback: @source_currency)
        @hotel = hotel
      end

      def call
        raise ArgumentError, "OTA financial currency is required" if @source_currency.blank? || @target_currency.blank?

        conversion = CurrencyConverter.convert(1, from: @source_currency, to: @target_currency, hotel: @hotel)
        raise ArgumentError, "Missing exchange rate from #{@source_currency} to #{@target_currency}" unless conversion

        @rate = conversion.rate.to_d
        @source = conversion.source
        stamp_amounts!(@financials)
        gross = convert(@financials[:gross_amount])
        eligible = component_hashes.reject { |component| component[:kind].to_s == "accommodation" }
        calculated = calculated_amount(:converted_amount)
        remainder = gross - calculated
        source_mismatch = @financials[:gross_amount].to_d - calculated_amount(:amount)
        rounding_adjustment = source_mismatch.zero? && eligible.any? ? remainder : 0.to_d
        if rounding_adjustment.nonzero? && eligible.any?
          component = eligible.reverse.find { |item| item[:kind].to_s == "tax" } || eligible.last
          component[:converted_amount] = component[:converted_amount].to_d + rounding_adjustment
          component[:conversion_rounding_amount] = rounding_adjustment
        end
        @financials[:converted_gross_amount] = gross
        @financials[:source_mismatch_amount] = source_mismatch
        @financials[:converted_currency] = @target_currency
        @financials[:exchange_rate] = @rate
        @financials[:exchange_rate_source] = @source
        @financials[:conversion_rounding_amount] = rounding_adjustment
        Result.new(payload: @financials, rate: @rate, source: @source, rounding_amount: rounding_adjustment)
      end

      private

      def stamp_amounts!(value)
        case value
        when Hash
          value[:converted_amount] = convert(value[:amount]) if value.key?(:amount) && monetary_component?(value)
          value.each_value { |nested| stamp_amounts!(nested) if nested.is_a?(Array) || nested.is_a?(Hash) }
        when Array
          value.each { |nested| stamp_amounts!(nested) }
        end
      end

      def monetary_component?(hash)
        hash.key?(:kind) || hash.key?(:date) || hash.key?(:position)
      end

      def component_hashes
        @component_hashes ||= begin
          entries = []
          Array(@financials[:rooms]).each do |room|
            room[:kind] = "accommodation"
            entries << room
            Array(room[:days]).each { |day| day[:kind] = "accommodation"; entries << day }
            %i[taxes service_fees discounts].each { |key| entries.concat(Array(room[key])) }
            Array(room[:days]).each do |day|
              %i[taxes service_fees discounts].each { |key| entries.concat(Array(day[key])) }
            end
          end
          %i[taxes service_fees discounts].each { |key| entries.concat(Array(@financials[key])) }
          entries
        end
      end

      def calculated_amount(amount_key)
        accommodations = Array(@financials[:rooms]).sum(0.to_d) do |room|
          days = Array(room[:days])
          days.any? ? days.sum(0.to_d) { |day| day[amount_key].to_d } : room[amount_key].to_d
        end
        charges = component_hashes.reject { |item| item[:kind] == "accommodation" }.sum(0.to_d) do |item|
          sign = item[:kind].to_s == "discount" ? -1 : (item[:kind].to_s == "tax" && item[:inclusive] ? 0 : 1)
          sign * item[amount_key].to_d
        end
        accommodations + charges
      end

      def convert(amount)
        (amount.to_d * @rate).round(CurrencyCatalog.precision_for(@target_currency))
      end
    end
  end
end
