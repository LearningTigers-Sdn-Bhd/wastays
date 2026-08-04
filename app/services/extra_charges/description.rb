# frozen_string_literal: true

module ExtraCharges
  class Description
    SEPARATOR = " · "

    def self.call(extra_charge:, currency:, amount: nil, calculated_amount: nil, quantity: 1,
      base_amount: nil, unit_rate: nil, date: nil, submitted_description: nil)
      new(
        extra_charge:, currency:, amount:, calculated_amount:, quantity:,
        base_amount:, unit_rate:, date:, submitted_description:
      ).call
    end

    def initialize(extra_charge:, currency:, amount:, calculated_amount:, quantity:, base_amount:, unit_rate:, date:, submitted_description:)
      @extra_charge = extra_charge
      @currency = currency
      @amount = amount
      @calculated_amount = calculated_amount
      @quantity = quantity.to_d
      @base_amount = base_amount
      @unit_rate = unit_rate
      @date = date
      @submitted_description = submitted_description
    end

    def call
      return @submitted_description.to_s.strip.presence || @extra_charge.name if @extra_charge.manual?

      [ @extra_charge.name, calculation, override_label, @date&.to_date&.iso8601 ].compact.join(SEPARATOR)
    end

    private

    def calculation
      return "#{decimal(@extra_charge.rate_value)}% × #{money(@base_amount)}" if @extra_charge.percentage?

      [ quantity_multiplier, money(actual_unit_rate) ].compact.join(" ")
    end

    def quantity_multiplier
      return unless @quantity > 1

      "#{decimal(@quantity)} ×"
    end

    def actual_unit_rate
      @unit_rate.presence || @extra_charge.rate_value
    end

    def override_label
      if total_overridden?
        "override #{money(@amount)}"
      elsif rate_overridden?
        "rate override"
      end
    end

    def total_overridden?
      return false unless @extra_charge.fixed? && @date.blank?
      return false if @amount.blank? || @calculated_amount.blank?

      @amount.to_d != @calculated_amount.to_d
    end

    def rate_overridden?
      @extra_charge.fixed? && @date.present? && @unit_rate.present? &&
        @unit_rate.to_d != @extra_charge.rate_value.to_d
    end

    def money(value)
      "#{@currency} #{format('%.2f', value.to_d)}"
    end

    def decimal(value)
      value.to_d.to_s("F").sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, "\\1")
    end
  end
end
