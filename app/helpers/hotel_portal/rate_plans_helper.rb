# frozen_string_literal: true

module HotelPortal
  module RatePlansHelper
    RoomSelectionScope = Struct.new(:room_type_id)

    def rate_plan_rate_mode_options(pricing)
      {
        "manual" => {
          label: "Set prices directly",
          hint: pricing.per_person? ? "Type the price for each number of adults." : "Type one nightly price for the room."
        },
        "derived" => {
          label: "Adjust Standard Rate",
          hint: "Start from this category's standard rate."
        },
        "auto" => {
          label: "Generate from a starting rate",
          hint: "Start from a rate you set, then step per adult."
        }
      }.slice(*pricing.available_modes)
    end

    def rate_plan_derive_choices
      [
        { label: "Adjust standard rate by %", value: "multiplier" },
        { label: "Adjust standard rate by amount", value: "offset" }
      ]
    end

    def rate_plan_step_unit_choices(currency)
      [ { label: currency, value: "amount" }, { label: "%", value: "percent" } ]
    end

    def rate_plan_money(amount, currency)
      "#{currency} #{number_with_precision(amount, precision: 2, delimiter: ',')}"
    end

    # A per-room assignment carries one figure whichever mode it is in, so
    # presence of pricing_value is the whole test. A per-guest one is only
    # complete when it prices every adult count the category can hold.
    def room_pricing_complete?(assignment, room_type, per_person: current_hotel.sells_per_person?)
      return room_type.base_price.present? if assignment&.rate_plan&.standard_rate? && !per_person
      return false unless assignment
      return assignment.pricing_value.present? unless per_person

      assignment.occupancy_prices.map(&:adults).sort == (1..room_type.max_adults).to_a
    end

    def room_pricing_summary(assignment, room_type, currency, per_person: current_hotel.sells_per_person?)
      return "Standard Rate #{money_summary(room_type.base_price, currency)}" if assignment&.rate_plan&.standard_rate? && !per_person
      return "Pricing not configured" unless assignment
      return "Adjusts Standard Rate" if assignment.derives_price?

      if per_person
        rungs = assignment.occupancy_prices.sort_by(&:adults)
        return "Pricing not configured" if rungs.empty?

        "#{currency} #{rungs.map { |rung| "#{rung.adults}p #{number_with_precision(rung.price, precision: 0, delimiter: ',')}" }.join(' · ')}"
      else
        money_summary(assignment.pricing_value, currency)
      end
    end

    def money_summary(amount, currency)
      "#{currency} #{number_with_precision(amount, precision: 2, delimiter: ',')}"
    end

    # "Walk-in"/"Corporate"/"OTA" say what the row is; "virtual tier" is an
    # internal notion staff have no reason to learn.
    TIER_LABELS = { "walk_in" => "Walk-in", "corporate" => "Corporate", "ota" => "OTA" }.freeze

    def rate_tier_label(rate_plan)
      TIER_LABELS[rate_plan.kind]
    end

    def age_band_pricing_choices
      [
        { label: "% of the adult rate", value: "multiplier" },
        { label: "Fixed price per child", value: "amount" }
      ]
    end
  end
end
