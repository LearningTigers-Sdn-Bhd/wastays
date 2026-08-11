module HotelOps
  class ApplyPricingRules
    ONLINE_PRIORITY = {
      gp: 1,
      wk: 2,
      sh: 3,
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
      RoomRate.reset_column_information
      room_types = @hotel.room_types.includes(:rate_plans)
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
      plans = %w[standard walk_in corporate].index_with { |kind| room_type.system_rate_plan(kind) }
      target_currency = plans.fetch("standard")&.currency || @hotel.default_currency || "MYR"

      (@start_date..@end_date).each do |date|
        apply_winner(room_type, plans.fetch("standard"), date, target_currency, winning_rule_for(date, category: :online))
        apply_winner(room_type, plans.fetch("walk_in"), date, target_currency, winning_rule_for(date, category: :walk_in))
        apply_winner(room_type, plans.fetch("corporate"), date, target_currency, winning_rule_for(date, category: :corporate))
      end
    end

    def apply_winner(room_type, rate_plan, date, currency, winner)
      return unless rate_plan

      rate = room_type.room_rates.find_or_initialize_by(rate_plan: rate_plan, date: date, currency: currency)
      old_value = rate.persisted? ? { date: date, price: rate.price&.to_f, rule_type: rate.applied_rule_type } : {}

      if winner.blank?
        return unless rate.persisted?

        rate.destroy!
        new_value = {}
      else
        rate.assign_attributes(price: winner.fetch(:price), applied_rule_type: winner.fetch(:tier).to_s)
        return unless rate.changed?

        rate.save!
        new_value = { date: date, price: rate.price.to_f, rule_type: rate.applied_rule_type }
      end

      @hotel.inventory_audit_logs.create!(
        room_type: room_type,
        user: @user,
        action_type: "rate_update",
        old_value: old_value,
        new_value: new_value,
        metadata: { source: "pricing_rules", rate_plan_id: rate_plan.id, rate_kind: rate_plan.kind }
      )
    end

    def winning_rule_for(date, category: :online)
      rules = []
      @hotel.pricing_rules.find_each do |pricing_rule|
        rule_cat = rule_category(pricing_rule.rule_type)
        next unless rule_cat == category

        tier = rule_tier(pricing_rule.rule_type)
        next if tier.blank?
        next unless rule_applies_for_date?(pricing_rule, date)

        rules << { tier: tier, price: pricing_rule.price, label: pricing_rule.name }
      end
      return nil if rules.empty?

      if category == :online
        rules.max_by { |rule| [ ONLINE_PRIORITY.fetch(rule[:tier]), rule[:price] ] }
      else
        rules.max_by { |rule| rule[:price] }
      end
    end

    def rule_category(rule_type)
      {
        "walk_in" => :walk_in,
        "corporate_rate" => :corporate,
        "ota_rate" => :ota
      }.fetch(rule_type, :online)
    end

    def rule_tier(rule_type)
      {
        "general" => :gp,
        "weekends" => :wk,
        "school_holiday" => :sh,
        "public_holiday" => :ph,
        "walk_in" => :wi,
        "corporate_rate" => :cr,
        "ota_rate" => :ota
      }[rule_type]
    end

    def rule_applies_for_date?(pricing_rule, date)
      case pricing_rule.rule_type
      when "general"
        within_rule_window?(pricing_rule, date)
      when "weekends"
        within_rule_window?(pricing_rule, date) && pricing_rule.weekdays.include?(date.wday)
      when "school_holiday", "public_holiday", "walk_in", "corporate_rate", "ota_rate"
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
