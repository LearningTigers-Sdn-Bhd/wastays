# frozen_string_literal: true

module HotelPortal
  module RatePlansHelper
    RoomSelectionScope = Struct.new(:room_type_id)
    OnboardingFieldScope = Struct.new(:rate_mode, :derive_mode, :adjustment_mode, :status)

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
      return money_summary(room_type.base_price, currency) if assignment&.rate_plan&.standard_rate? && !per_person
      return "Not priced" unless assignment

      if per_person
        rungs = assignment.occupancy_prices.sort_by(&:adults)
        return "Not priced" if rungs.empty?

        "#{currency} #{rungs.map { |rung| "#{rung.adults}p #{number_with_precision(rung.price, precision: 0, delimiter: ',')}" }.join(' · ')}"
      else
        return "Not priced" if assignment.pricing_value.blank?
        return "Adjusts Standard Rate" if assignment.derives_price?

        money_summary(assignment.pricing_value, currency)
      end
    end

    def money_summary(amount, currency)
      "#{currency} #{number_with_precision(amount, precision: 2, delimiter: ',')}"
    end

    # Onboarding submits a rate plan's assignments as either an array or the
    # index-keyed hash a cloned row produces; both mean the same list.
    def plan_entry_assignments(entry)
      value = entry["assignments"]
      value.respond_to?(:values) ? value.values : Array(value)
    end

    # Onboarding folds rate mode and derive mode into one choice. Two selects for
    # what is really one decision — how this plan gets its prices — is the kind of
    # split that made the old sheet hard to read.
    def rate_plan_pricing_basis_choices
      [
        { label: "Set prices directly", value: "manual" },
        { label: "Standard Rate ± %", value: "derived_multiplier" },
        { label: "Standard Rate ± amount", value: "derived_offset" }
      ]
    end

    def rate_plan_pricing_basis(entry)
      return "manual" unless entry["rate_mode"].to_s == "derived"

      entry["derive_mode"].to_s == "offset" ? "derived_offset" : "derived_multiplier"
    end

    def rate_plan_derived?(entry)
      rate_plan_pricing_basis(entry) != "manual"
    end

    # A band column is headed by its label, falling back to the ages it covers
    # so an unnamed band is still identifiable while it is being typed.
    def child_band_column_label(band, index)
      band["label"].presence || begin
        ages = [ band["min_age"], band["max_age"] ].map(&:presence)
        ages.all? ? "Ages #{ages.first}–#{ages.last}" : "Band #{index + 1}"
      end
    end

    def child_band_column_header(band, index, read_only: false)
      label = child_band_column_label(band, index)
      mode = band["pricing_mode"].presence || "amount"

      tag.div(class: "flex min-w-24 flex-col items-start gap-2") do
        safe_join([
          tag.span(label),
          render(PanelsUI::Switch.new(
            name: "child_bands[#{index}][pricing_mode]",
            value: "multiplier",
            unchecked_value: "amount",
            checked: mode == "multiplier",
            disabled: read_only,
            label: "Use percentage of the one-adult price for #{label}",
            label_hidden: true,
            variant: :icon,
            size: :md,
            off_icon: "dollar-sign",
            on_icon: "percent"
          ))
        ])
      end
    end

    def age_band_pricing_choices
      [
        { label: "% of the adult rate", value: "multiplier" },
        { label: "Fixed price per child", value: "amount" }
      ]
    end
  end
end
