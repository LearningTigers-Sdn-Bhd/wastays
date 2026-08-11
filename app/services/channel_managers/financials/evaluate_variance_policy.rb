# frozen_string_literal: true

module ChannelManagers
  module Financials
    class EvaluateVariancePolicy
      Result = Data.define(:accepted, :snapshot)

      def self.call(hotel:, variance_amount:, expected_amount:, room_nights:)
        policy = OtaRateVariancePolicy.find_by(hotel: hotel) || OtaRateVariancePolicy.new(hotel: hotel, mode: "recommended", currency: hotel.default_currency)
        policy.valid?
        amount = variance_amount.to_d.abs
        percentage = expected_amount.to_d.zero? ? 0.to_d : amount * 100 / expected_amount.to_d
        accepted = if policy.mode == "strict"
          amount.zero?
        else
          percentage <= policy.maximum_percentage.to_d &&
            amount <= policy.maximum_amount_per_room_night.to_d * [ room_nights.to_i, 1 ].max
        end
        Result.new(accepted:, snapshot: {
          "mode" => policy.mode, "maximum_percentage" => policy.maximum_percentage.to_d.to_s("F"),
          "maximum_amount_per_room_night" => policy.maximum_amount_per_room_night.to_d.to_s("F"),
          "currency" => policy.currency
        })
      end
    end
  end
end
