module HotelOps
  class ApplyPricingRules
    PRIORITY = {
      gp: 1,
      wk: 2,
      sc: 3,
      ph: 4
    }.freeze

    def initialize(hotel:, room_type_ids: [], start_date:, end_date:, user:)
      @hotel = hotel
      @room_type_ids = room_type_ids
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @user = user
    end

    def call
      room_types = @hotel.room_types
      room_types = room_types.where(id: @room_type_ids) if @room_type_ids.present?

      ActiveRecord::Base.transaction do
        room_types.find_each do |room_type|
          apply_for_room_type(room_type)
        end
      end

      { success: true }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def apply_for_room_type(room_type)
      standard_plan = room_type.rate_plans.first
      target_currency = standard_plan&.currency || @hotel.default_currency || "MYR"

      (@start_date..@end_date).each do |date|
        winner = winning_rule_for(date)

        rate = room_type.room_rates.find_or_initialize_by(date: date, currency: target_currency)
        if winner.blank?
          rate.destroy! if rate.persisted?
          next
        end

        old_price = rate.price
        old_currency = rate.currency

        rate.price = winner[:price]
        rate.currency = target_currency
        rate.rate_plan = standard_plan if standard_plan
        rate.save!

        next if old_price == winner[:price] && old_currency == rate.currency

        @hotel.inventory_audit_logs.create!(
          room_type: room_type,
          user: @user,
          action_type: "rate_update",
          old_value: { date: date, price: old_price.to_f },
          new_value: { date: date, price: winner[:price].to_f },
          metadata: { source: "pricing_rules", tier: winner[:tier].to_s, label: winner[:label] }
        )
      end
    end

    def winning_rule_for(date)
      rules = []
      @hotel.pricing_rules.find_each do |pricing_rule|
        tier = rule_tier(pricing_rule.rule_type)
        next if tier.blank?
        next unless rule_applies_for_date?(pricing_rule, date)

        rules << { tier: tier, price: pricing_rule.price, label: pricing_rule.name }
      end
      return nil if rules.empty?

      rules.max_by { |rule| [ rule[:price], PRIORITY.fetch(rule[:tier]) ] }
    end

    def rule_tier(rule_type)
      {
        "general" => :gp,
        "weekends" => :wk,
        "school_holiday" => :sc,
        "public_holiday" => :ph
      }[rule_type]
    end

    def rule_applies_for_date?(pricing_rule, date)
      case pricing_rule.rule_type
      when "general"
        within_rule_window?(pricing_rule, date)
      when "weekends"
        within_rule_window?(pricing_rule, date) && pricing_rule.weekdays.include?(date.wday)
      when "school_holiday", "public_holiday"
        within_rule_window?(pricing_rule, date)
      else
        false
      end
    end

    def within_rule_window?(pricing_rule, date)
      return false if pricing_rule.start_date.blank? || pricing_rule.end_date.blank?

      (pricing_rule.start_date..pricing_rule.end_date).cover?(date)
    end
  end
end
