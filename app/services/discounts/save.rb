# frozen_string_literal: true

module Discounts
  class Save
    Result = ApplicationResult.define(:discount)

    def self.call(discount:, attributes:)
      new(discount:, attributes:).call
    end

    def initialize(discount:, attributes:)
      @discount = discount
      @transaction_code = discount.transaction_code
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      saved = false
      ActiveRecord::Base.transaction do
        assign_attributes
        raise ActiveRecord::Rollback unless records_valid?

        @transaction_code.save!
        @discount.save!
        saved = true
      end
      saved ? Result.success(discount: @discount) : failure
    rescue ActiveRecord::RecordInvalid => error
      copy_errors(error.record)
      failure
    end

    private

    def assign_attributes
      @transaction_code.assign_attributes(
        name: @attributes[:name], code: normalize_code(@attributes[:code]), kind: "adjustment",
        category: "discount", active: boolean(:active), is_taxable: false
      )
      if @transaction_code.new_record?
        @transaction_code.system_key = unique_system_key(@transaction_code.code)
        @transaction_code.system_required = false
      end

      pricing_type = @attributes[:pricing_type]
      @discount.assign_attributes(
        description: @attributes[:description], pricing_type: pricing_type,
        rate_value: pricing_type == "manual" ? nil : @attributes[:rate_value],
        application_scope: @attributes[:application_scope],
        allow_amount_override: pricing_type == "manual" || (pricing_type == "fixed" && boolean(:allow_amount_override)),
        position: @discount.position || 0
      )
      codes = if @discount.application_scope == "selected_charges"
        requested_ids = Array(@attributes[:applicable_transaction_code_ids]).reject(&:blank?).map(&:to_s).uniq
        available = @discount.hotel.transaction_codes.active.where(kind: "charge", id: requested_ids)
        invalid_selection = available.pluck(:id).map(&:to_s).sort != requested_ids.sort
        @invalid_applicable_codes = invalid_selection
        available
      else
        @discount.hotel.transaction_codes.none
      end
      @discount.applicable_transaction_codes = codes
    end

    def records_valid?
      code_valid = @transaction_code.valid?
      discount_valid = @discount.valid?
      if @invalid_applicable_codes
        @discount.errors.add(:applicable_transaction_codes, "include an unavailable charge code")
        discount_valid = false
      end
      copy_errors(@transaction_code) unless code_valid
      code_valid && discount_valid && @discount.errors.empty?
    end

    def copy_errors(record)
      return if record.blank? || record == @discount

      record.errors.each do |error|
        @discount.errors.add(error.attribute, error.message) unless @discount.errors.added?(error.attribute, error.message)
      end
    end

    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    def unique_system_key(code)
      base = "discount_#{code.to_s.parameterize(separator: '_').presence || 'discount'}"
      candidate = base
      suffix = 2
      while @discount.hotel.transaction_codes.exists?(system_key: candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end

    def boolean(key)
      !!ActiveModel::Type::Boolean.new.cast(@attributes[key])
    end

    def failure
      Result.failure(@discount.errors.full_messages.to_sentence, discount: @discount)
    end
  end
end
