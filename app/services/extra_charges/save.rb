# frozen_string_literal: true

module ExtraCharges
  class Save
    Result = Data.define(:success?, :extra_charge)

    def self.call(extra_charge:, attributes:, tax_rule_keys:)
      new(extra_charge:, attributes:, tax_rule_keys:).call
    end

    def initialize(extra_charge:, attributes:, tax_rule_keys:)
      @extra_charge = extra_charge
      @transaction_code = extra_charge.transaction_code
      @attributes = attributes.to_h.with_indifferent_access
      @tax_rule_keys = Array(tax_rule_keys).reject(&:blank?).uniq
    end

    def call
      assign_attributes
      return failure unless records_valid?

      ActiveRecord::Base.transaction do
        @transaction_code.save!
        @extra_charge.save!
        assign_tax_rules!
      end

      Result.new(success?: true, extra_charge: @extra_charge)
    rescue ActiveRecord::RecordInvalid => error
      copy_errors(error.record)
      failure
    end

    private

    def assign_attributes
      @transaction_code.assign_attributes(
        name: @attributes[:name],
        code: normalize_code(@attributes[:code]),
        category: @attributes[:category].presence || "other",
        active: ActiveModel::Type::Boolean.new.cast(@attributes[:active]),
        kind: "charge"
      )
      if @transaction_code.new_record?
        @transaction_code.system_key = unique_system_key(@transaction_code.code)
        @transaction_code.system_required = false
      end

      @extra_charge.assign_attributes(
        description: @attributes[:description],
        pricing_type: @attributes[:pricing_type],
        rate_value: normalized_rate_value,
        charging_unit: @attributes[:charging_unit].presence || "per_item",
        percentage_basis: (@attributes[:percentage_basis] if @attributes[:pricing_type] == "percentage"),
        allow_amount_override: allow_amount_override,
        position: @attributes[:position].presence || @extra_charge.position || 0
      )
      @transaction_code.is_taxable = @tax_rule_keys.any?
    end

    def records_valid?
      transaction_code_valid = @transaction_code.valid?
      extra_charge_valid = @extra_charge.valid?
      copy_errors(@transaction_code) unless transaction_code_valid
      transaction_code_valid && extra_charge_valid
    end

    def copy_errors(record)
      return if record == @extra_charge

      record.errors.each do |error|
        @extra_charge.errors.add(error.attribute, error.message) unless @extra_charge.errors.added?(error.attribute, error.message)
      end
    end

    def normalized_rate_value
      return nil if @attributes[:pricing_type] == "manual"

      @attributes[:rate_value]
    end

    def allow_amount_override
      return true if @attributes[:pricing_type] == "manual"
      return false if @attributes[:pricing_type] == "percentage"

      ActiveModel::Type::Boolean.new.cast(@attributes[:allow_amount_override])
    end

    def assign_tax_rules!
      @transaction_code.transaction_code_taxes.destroy_all
      custom_ids = @tax_rule_keys.filter_map { |key| key.delete_prefix("hotel_tax:") if key.start_with?("hotel_tax:") }
      primary_keys = @tax_rule_keys.filter_map { |key| key.delete_prefix("primary:") if key.start_with?("primary:") }

      @extra_charge.hotel.hotel_taxes.where(id: custom_ids).find_each do |tax|
        @transaction_code.transaction_code_taxes.create!(hotel_tax: tax)
      end
      (primary_keys & TransactionCodeTax::PRIMARY_TAX_KEYS).each do |primary_tax_key|
        @transaction_code.transaction_code_taxes.create!(primary_tax_key: primary_tax_key)
      end
    end

    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    def unique_system_key(code)
      base = "extra_charge_#{code.to_s.parameterize(separator: "_").presence || "charge"}"
      candidate = base
      suffix = 2
      while @extra_charge.hotel.transaction_codes.exists?(system_key: candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end

    def failure
      Result.new(success?: false, extra_charge: @extra_charge)
    end
  end
end
