# frozen_string_literal: true

module PaymentMethods
  class Save
    Result = ApplicationResult.define(:payment_method)

    def self.call(payment_method:, attributes:)
      new(payment_method:, attributes:).call
    end

    def initialize(payment_method:, attributes:)
      @payment_method = payment_method
      @transaction_code = payment_method.transaction_code
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      assign_attributes
      return failure unless records_valid?

      @payment_method.hotel.with_lock do
        ActiveRecord::Base.transaction do
          if @payment_method.default_cash?
            @payment_method.hotel.hotel_payment_methods.where(default_cash: true).where.not(id: @payment_method.id).update_all(default_cash: false, updated_at: Time.current)
          end
          @transaction_code.save!
          @payment_method.save!
        end
      end

      Result.success(payment_method: @payment_method)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      copy_errors(error.record) if error.respond_to?(:record)
      @payment_method.errors.add(:default_cash, "has already been selected") if error.is_a?(ActiveRecord::RecordNotUnique)
      failure
    end

    private

    def assign_attributes
      @payment_method.assign_attributes(
        payment_method_type: @attributes[:payment_method_type],
        default_cash: boolean(:default_cash),
        guest_advance: boolean(:guest_advance),
        surcharge_posting_type: surcharge_enabled? ? @attributes[:surcharge_posting_type].presence : nil,
        surcharge_value: surcharge_enabled? ? @attributes[:surcharge_value].presence : nil,
        surcharge_extra_charge_id: surcharge_enabled? ? @attributes[:surcharge_extra_charge_id].presence : nil,
        position: @payment_method.position || 0
      )
      @transaction_code.assign_attributes(
        name: @attributes[:name],
        code: normalize_code(@attributes[:code]),
        kind: "payment",
        category: @payment_method.expected_category,
        active: @attributes.key?(:active) ? boolean(:active) : @transaction_code.active,
        is_taxable: false
      )
      return unless @transaction_code.new_record?

      @transaction_code.system_key = unique_system_key(@transaction_code.code)
      @transaction_code.system_required = false
    end

    def records_valid?
      code_valid = @transaction_code.valid?
      method_valid = @payment_method.valid?
      copy_errors(@transaction_code) unless code_valid
      code_valid && method_valid
    end

    def copy_errors(record)
      return if record.blank? || record == @payment_method

      record.errors.each do |error|
        @payment_method.errors.add(error.attribute, error.message) unless @payment_method.errors.added?(error.attribute, error.message)
      end
    end

    def boolean(key)
      !!ActiveModel::Type::Boolean.new.cast(@attributes[key])
    end

    def surcharge_enabled?
      boolean(:surcharge_enabled)
    end

    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    def unique_system_key(code)
      base = "payment_method_#{code.to_s.parameterize(separator: '_').presence || 'payment'}"
      candidate = base
      suffix = 2
      while @payment_method.hotel.transaction_codes.exists?(system_key: candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end

    def failure
      Result.failure(@payment_method.errors.full_messages.to_sentence, payment_method: @payment_method)
    end
  end
end
