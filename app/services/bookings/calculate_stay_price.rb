# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:)
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = @room_type.room_rates.find_by(date: date)
        rate&.price || @room_type.base_price
      end
    end
  end
end
