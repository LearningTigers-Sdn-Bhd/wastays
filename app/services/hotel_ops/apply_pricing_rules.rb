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
      standard_plan = room_type.standard_rate_plan
      target_currency = standard_plan&.currency || @hotel.default_currency || "MYR"

      (@start_date..@end_date).each do |date|
        online_winner = winning_rule_for(date, category: :online)
        walk_in_winner = winning_rule_for(date, category: :walk_in)
        corporate_winner = winning_rule_for(date, category: :corporate)

        rate = anchor_rate_for(room_type, standard_plan, date, target_currency)
        if online_winner.blank? && walk_in_winner.blank? && corporate_winner.blank?
          rate.destroy! if rate.persisted?
          next
        end

        old_price = rate.price
        old_wi_price = rate.walk_in_price
        old_cr_price = rate.corporate_price
        old_rule_type = rate.applied_rule_type
        old_currency = rate.currency

        # Fallback to base_price if no online rule applies but we are saving a rate record
        rate.price = online_winner&.dig(:price) || room_type.base_price
        rate.applied_rule_type = online_winner&.dig(:tier)&.to_s || "base"
        rate.walk_in_price = walk_in_winner&.dig(:price)
        rate.corporate_price = corporate_winner&.dig(:price)
        rate.currency = target_currency
        rate.rate_plan = standard_plan if standard_plan
        rate.save!

        next if old_price == rate.price && old_wi_price == rate.walk_in_price && old_cr_price == rate.corporate_price && old_currency == rate.currency && old_rule_type == rate.applied_rule_type

        @hotel.inventory_audit_logs.create!(
          room_type: room_type,
          user: @user,
          action_type: "rate_update",
          old_value: { date: date, price: old_price.to_f, walk_in_price: old_wi_price&.to_f, corporate_price: old_cr_price&.to_f, rule_type: old_rule_type },
          new_value: { date: date, price: rate.price&.to_f, walk_in_price: rate.walk_in_price&.to_f, corporate_price: rate.corporate_price&.to_f, rule_type: rate.applied_rule_type },
          metadata: {
            source: "pricing_rules",
            online_tier: online_winner&.dig(:tier)&.to_s,
            walk_in_tier: walk_in_winner&.dig(:tier)&.to_s,
            corporate_tier: corporate_winner&.dig(:tier)&.to_s
          }
        )
      end
    end

    # The row these rules own: the anchor plan's row for the date.
    #
    # The lookup used to carry no rate_plan at all, so it took whichever row the
    # category returned for the date. On a category carrying a second plan that
    # is often the second plan's row, which was then overwritten with the rule
    # price and re-pointed at the anchor: either a unique-index violation
    # against the anchor's own row, or — when the anchor had no row yet — the
    # second plan silently losing its price for that date. destroy! could take
    # it the same way.
    #
    # An unattributed row is still adopted rather than left behind: rows predating
    # rate_plan_id are the anchor row in legacy data, and CalculateStayPrice
    # reads them through its nil fallback. Only the anchor's own row outranks
    # them, so nothing that belongs to another plan is ever claimed.
    def anchor_rate_for(room_type, standard_plan, date, currency)
      scope = room_type.room_rates.where(date: date, currency: currency)

      scope.find_by(rate_plan: standard_plan) ||
        scope.find_by(rate_plan: nil) ||
        room_type.room_rates.build(rate_plan: standard_plan, date: date, currency: currency)
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
