# frozen_string_literal: true

module HotelPortal
  module RatePlanWizardsHelper
    # The sheet footer owns the submit buttons, so it needs the id of the form
    # sitting in the body — that is what the HTML `form` attribute binds them to.
    def wizard_form_id(step, room_type = nil)
      step == RatePlanWizard::STEP_DETAILS ? "rate-plan-wizard-details" : "rate-plan-wizard-room-#{room_type&.id}"
    end

    def wizard_step_label(wizard, step)
      case step
      when RatePlanWizard::STEP_DETAILS then "Plan details"
      when RatePlanWizard::STEP_REVIEW then "Review"
      else wizard.room_type_for_step(step)&.name || "Room"
      end
    end

    # Per-room properties price the room once, so deriving from the standard rate
    # is the only alternative to typing a figure. Per-person properties get a
    # third: the same ladder, anchored on a rate typed here instead.
    def wizard_rate_mode_options(pricing)
      {
        "manual" => {
          label: "Manual",
          hint: pricing.per_person? ? "Type the price for each number of adults." : "Type one nightly price for the room."
        },
        "derived" => {
          label: "Derived",
          hint: "Start from this category's standard rate."
        },
        "auto" => {
          label: "Auto",
          hint: "Start from a rate you set, then step per adult."
        }
      }.slice(*pricing.available_modes)
    end

    def wizard_derive_choices
      [
        { label: "Adjust standard rate by %", value: "multiplier" },
        { label: "Adjust standard rate by amount", value: "offset" }
      ]
    end

    def wizard_step_unit_choices(currency)
      [ { label: currency, value: "amount" }, { label: "%", value: "percent" } ]
    end

    def wizard_money(amount, currency)
      "#{currency} #{number_with_precision(amount, precision: 2, delimiter: ',')}"
    end

    # One line summarising a priced category on the review step.
    def wizard_matrix_summary(pricing, currency)
      matrix = pricing.occupancy_matrix
      return wizard_per_room_summary(pricing, currency) if matrix.empty?

      matrix.map { |adults, price| "#{adults}p #{number_with_precision(price, precision: 2, delimiter: ',')}" }.join(" · ")
    end

    def wizard_per_room_summary(pricing, currency)
      return wizard_money(pricing.default_rate, currency) unless pricing.derived?

      sign = pricing.derive_value.to_d.negative? ? "" : "+"
      unit = pricing.derive_mode == "multiplier" ? "%" : " #{currency}"
      "Standard rate #{sign}#{number_with_precision(pricing.derive_value, precision: 2)}#{unit}"
    end
  end
end
