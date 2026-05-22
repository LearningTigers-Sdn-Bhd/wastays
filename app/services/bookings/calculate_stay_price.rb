# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, corporate_rate: false)
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @corporate_rate = corporate_rate
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = @room_type.room_rates.find_by(date: date)
        if @corporate_rate
          rate&.corporate_price || rate&.price || @room_type.base_price
        else
          rate&.walk_in_price || rate&.price || @room_type.base_price
        end
      end
    end
  end
end
