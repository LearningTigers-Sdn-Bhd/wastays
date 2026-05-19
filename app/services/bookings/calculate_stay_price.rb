# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, rate_plan: nil)
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @rate_plan = rate_plan
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = room_rate_for(date)
        rate&.price || @room_type.base_price
      end
    end

    private

    def room_rate_for(date)
      scope = @room_type.room_rates.where(date: date)
      return scope.find_by(rate_plan: @rate_plan) if @rate_plan.present?

      scope.find_by(rate_plan_id: nil)
    end
  end
end
