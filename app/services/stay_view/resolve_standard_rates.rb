# frozen_string_literal: true

module StayView
  class ResolveStandardRates
    def self.call(room_types:, standard_rates:, dates:, selected_rate_plan: nil)
      new(room_types:, standard_rates:, dates:, selected_rate_plan:).call
    end

    def initialize(room_types:, standard_rates:, dates:, selected_rate_plan: nil)
      @room_types = room_types
      @standard_rates = standard_rates
      @dates = dates.map(&:to_date)
      @selected_rate_plan = selected_rate_plan
    end

    def call
      rates_by_key = standard_rates.index_by do |rate|
        [ rate.room_type_id, rate.rate_plan_id, rate.date, rate.currency ]
      end

      room_types.each_with_object({}) do |room_type, result|
        currency = selected_rate_plan&.currency || room_type.rate_currency
        next if currency.blank?
        next if selected_rate_plan && !room_type.id.in?(selected_rate_plan.room_type_ids)

        dates.each do |date|
          dated_rate = if selected_rate_plan
            rates_by_key[[ room_type.id, selected_rate_plan.id, date, currency ]]
          else
            rates_by_key[[ room_type.id, room_type.master_rate_plan_id, date, currency ]] ||
              rates_by_key[[ room_type.id, nil, date, currency ]]
          end

          result[[ room_type.id, date ]] = if dated_rate
            StandardRate.new(amount: dated_rate.price, currency:, source: :room_rate)
          elsif !selected_rate_plan && room_type.base_price.present?
            StandardRate.new(amount: room_type.base_price, currency:, source: :base_price_fallback)
          end
        end
      end.freeze
    end

    private

    attr_reader :room_types, :standard_rates, :dates, :selected_rate_plan
  end
end
