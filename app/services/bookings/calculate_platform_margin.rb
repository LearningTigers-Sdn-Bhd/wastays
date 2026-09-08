# frozen_string_literal: true

module Bookings
  class CalculatePlatformMargin
    Result = Data.define(:rate, :amount)

    def self.call(hotel:, room_total:)
      rate = hotel.effective_margin_rate.to_d
      amount = (room_total.to_d * rate / 100).round(2)

      Result.new(rate: rate, amount: amount)
    end
  end
end
