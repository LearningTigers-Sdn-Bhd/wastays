# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, rate_plan: nil, corporate_rate: false, rate_tier: :standard, pax: nil, adults: nil, children: nil, infants: nil)
      @room_type = room_type
      @check_in = check_in&.to_date
      @check_out = check_out&.to_date
      @rate_plan = rate_plan
      @corporate_rate = corporate_rate
      @rate_tier = rate_tier.to_sym

      @adults = (adults || pax || 2).to_i
      @children = (children || 0).to_i
      @infants = (infants || 0).to_i
      @pax = @adults + @children + @infants
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = room_rate_for(date)
        base_nightly_rate = tier_price(rate) || rate&.price || @room_type.base_price

        if @rate_plan&.sell_mode == "per_person"
          child_multiplier = @rate_plan.child_price_multiplier || 1.to_d
          infant_multiplier = @rate_plan.infant_price_multiplier || 0.to_d

          adults_cost = @adults * base_nightly_rate
          children_cost = @children * base_nightly_rate * child_multiplier
          infants_cost = @infants * base_nightly_rate * infant_multiplier

          price = adults_cost + children_cost + infants_cost

          if @pax == 1
            supplement = rate&.single_supplement || @rate_plan.single_supplement || 0.to_d
            price += supplement
          end
          price
        else
          price = base_nightly_rate

          base_occ = rate&.base_occupancy || @rate_plan&.base_occupancy || 2
          extra_charge = rate&.extra_pax_charge || @rate_plan&.extra_pax_charge || 0.to_d

          billable_pax = @adults + @children
          if billable_pax > base_occ && extra_charge.positive?
            extra_guests = billable_pax - base_occ
            price += extra_guests * extra_charge
          end

          price
        end
      end
    end

    private

    def tier_price(rate)
      return nil if rate.blank?

      case @rate_tier
      when :corporate then rate.corporate_price
      when :walk_in then rate.walk_in_price
      when :ota then rate.ota_price
      else
        @corporate_rate ? rate.corporate_price : nil
      end
    end

    def room_rate_for(date)
      scope = @room_type.room_rates.where(date: date)

      plans_to_try = [ @rate_plan, @room_type.rate_plans.first, nil ].uniq

      plans_to_try.each do |plan|
        rate = scope.find_by(rate_plan: plan)
        return rate if rate.present?
      end

      nil
    end
  end
end
