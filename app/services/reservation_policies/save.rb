# frozen_string_literal: true

module ReservationPolicies
  # Updates a stay-event policy and, for cancellation, its tiers.
  #
  # Unlike the Commercial registries, this never creates a transaction code: the
  # four policies hang off codes Financials::EnsureDefaultTransactionCodes already
  # seeds, and a hotel cannot invent a fifth kind of stay event. Only the policy is
  # editable — name, code, kind and taxability all belong to ROOM.
  class Save
    Result = ApplicationResult.define(:policy)

    def self.call(policy:, attributes:)
      new(policy: policy, attributes: attributes).call
    end

    def initialize(policy:, attributes:)
      @policy = policy
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      saved = false
      ActiveRecord::Base.transaction do
        assign_attributes
        assign_tiers if @policy.cancellation?
        raise ActiveRecord::Rollback unless @policy.valid?

        @policy.save!
        saved = true
      end

      saved ? Result.success(policy: @policy) : failure
    rescue ActiveRecord::RecordInvalid => error
      copy_errors(error.record)
      failure
    end

    private

    # The sheet hides and *disables* everything beneath the gate switch when the
    # policy is turned off, and a disabled input is not submitted at all. So an
    # absent attribute means "leave it alone", never "clear it". Assigning what was
    # missing would blank a nights policy's rate and fail its own validation on the
    # way out — and quietly take the hotel's guest note and refund terms with it.
    def assign_attributes
      pricing_type = @attributes[:pricing_type].presence || @policy.pricing_type

      @policy.assign_attributes(
        active: boolean(:active),
        pricing_type: pricing_type,
        # A manual policy is nothing but the override path, so the flag is moot;
        # a computed one only offers "custom" when the hotel says it may.
        allow_amount_override: pricing_type == "manual" || boolean(:allow_amount_override)
      )

      assign_pricing(pricing_type)
      assign_if_submitted(:description)
      assign_refund_terms if @policy.cancellation?
    end

    def assign_pricing(pricing_type)
      # Switching to manual is the one case where clearing is the intent: there is
      # no configured amount to keep.
      return @policy.assign_attributes(rate_value: nil, percentage_basis: nil) if pricing_type == "manual"

      assign_if_submitted(:rate_value)
      pricing_type == "percentage" ? assign_if_submitted(:percentage_basis) : @policy.percentage_basis = nil
    end

    def assign_refund_terms
      assign_if_submitted(:refund_processing_days) { |value| value.presence }
      assign_if_submitted(:refund_method) { |value| value.presence }
    end

    def assign_if_submitted(key)
      return unless @attributes.key?(key)

      value = @attributes[key]
      @policy.public_send(:"#{key}=", block_given? ? yield(value) : value)
    end

    def assign_tiers
      return if @attributes[:cancellation_tiers_attributes].blank?

      @policy.cancellation_tiers_attributes = normalized_tiers
    end

    # A tier only carries a basis when it is a percentage; leaving a stale basis on
    # a fixed tier would trip the check constraint.
    def normalized_tiers
      tiers_attributes.each_with_object({}).with_index do |((key, attributes), result), index|
        pricing_type = attributes[:pricing_type].presence || "percentage"
        result[key] = attributes.merge(
          pricing_type: pricing_type,
          percentage_basis: pricing_type == "percentage" ? attributes[:percentage_basis].presence : nil,
          position: index + 1
        )
      end
    end

    def tiers_attributes
      @attributes[:cancellation_tiers_attributes].to_h.reject do |_key, attributes|
        attributes[:days_before_arrival].blank? && attributes[:rate_value].blank?
      end
    end

    def boolean(key)
      return @policy.public_send(key) unless @attributes.key?(key)

      ActiveModel::Type::Boolean.new.cast(@attributes[key])
    end

    def copy_errors(record)
      return if record == @policy

      record.errors.full_messages.each { |message| @policy.errors.add(:base, message) }
    end

    def failure
      Result.failure(@policy.errors.full_messages.to_sentence.presence || "Reservation policy could not be saved.", policy: @policy)
    end
  end
end
