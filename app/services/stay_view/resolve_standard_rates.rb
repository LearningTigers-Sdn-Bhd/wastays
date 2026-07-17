# frozen_string_literal: true

module StayView
  class ResolveStandardRates
    def self.call(room_types:, standard_rates:, dates:)
      new(room_types:, standard_rates:, dates:).call
    end

    def initialize(room_types:, standard_rates:, dates:)
      @room_types = room_types
      @standard_rates = standard_rates
      @dates = dates.map(&:to_date)
    end

    def call
      rates_by_key = standard_rates.index_by do |rate|
        [ rate.room_type_id, rate.rate_plan_id, rate.date, rate.currency ]
      end

      room_types.each_with_object({}) do |room_type, result|
        next if room_type.rate_currency.blank?

        dates.each do |date|
          dated_rate = rates_by_key[[ room_type.id, room_type.master_rate_plan_id, date, room_type.rate_currency ]] ||
            rates_by_key[[ room_type.id, nil, date, room_type.rate_currency ]]

          result[[ room_type.id, date ]] = if dated_rate
            StandardRate.new(amount: dated_rate.price, currency: room_type.rate_currency, source: :room_rate)
          elsif room_type.base_price.present?
            StandardRate.new(amount: room_type.base_price, currency: room_type.rate_currency, source: :base_price_fallback)
          end
        end
      end.freeze
    end

    private

    attr_reader :room_types, :standard_rates, :dates
  end
end
