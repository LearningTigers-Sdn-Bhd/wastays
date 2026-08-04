# frozen_string_literal: true

module Deposits
  class ApplyAcrossFolios
    STRATEGIES = %w[manual proportional outstanding_balance].freeze

    def self.call(deposit:, folios:, amount:, strategy:, actor: nil, manual_amounts: {}, operation_key: nil,
      posting_date: nil, override_night_audit: false, override_reason: nil, metadata: {})
      new(deposit:, folios:, amount:, strategy:, actor:, manual_amounts:, operation_key:, posting_date:,
        override_night_audit:, override_reason:, metadata:).call
    end

    def initialize(deposit:, folios:, amount:, strategy:, actor:, manual_amounts:, operation_key:, posting_date:,
      override_night_audit:, override_reason:, metadata:)
      @deposit = deposit
      @folios = Array(folios).uniq
      @amount = amount.to_d
      @strategy = strategy.to_s
      @actor = actor
      @manual_amounts = manual_amounts.to_h.transform_keys(&:to_s)
      @operation_key = operation_key.to_s.presence
      @posting_date = posting_date
      @override_night_audit = override_night_audit
      @override_reason = override_reason
      @metadata = metadata.to_h
    end

    def call
      return failure("Unknown application strategy.") unless @strategy.in?(STRATEGIES)
      return failure("Select at least one folio.") if @folios.empty?
      return failure("Application amount must be positive.") unless @amount.positive?
      existing = existing_operation_movements
      return Deposits::BatchResult.success(movements: existing) if existing

      plan = application_plan
      return failure("Application plan must equal the requested amount.") unless plan.values.sum == @amount
      existing = existing_movements(plan)
      return Deposits::BatchResult.success(movements: existing) if existing
      return failure("Application exceeds the available deposit amount.") if @amount > @deposit.available_amount

      movements = []
      Deposit.transaction do
        plan.each_with_index do |(folio, value), index|
          next unless value.positive?

          result = Deposits::Apply.call(
            deposit: @deposit,
            booking_folio: folio,
            amount: value,
            actor: @actor,
            posting_date: @posting_date,
            override_night_audit: @override_night_audit,
            override_reason: @override_reason,
            operation_key: @operation_key && "#{@operation_key}:#{index}:#{folio.id}",
            metadata: @metadata
          )
          raise ActiveRecord::Rollback, (@error = result.error) unless result.success?

          movements << result.movement
        end
      end
      return failure(@error) if @error

      Deposits::BatchResult.success(movements: movements)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def existing_operation_movements
      return if @operation_key.blank?

      movements = @deposit.deposit_movements.movement_type_apply.where.not(operation_key: nil).select do |movement|
        movement.operation_key.start_with?("#{@operation_key}:")
      end
      return if movements.empty?
      return unless movements.sum(&:amount) == @amount
      return unless movements.all? { |movement| @folios.any? { |folio| folio.id == movement.booking_folio_id } }

      movements.sort_by(&:operation_key)
    end

    def existing_movements(plan)
      return if @operation_key.blank?

      expected = plan.each_with_index.filter_map do |(folio, value), index|
        next unless value.positive?

        [ "#{@operation_key}:#{index}:#{folio.id}", folio, value ]
      end
      movements = DepositMovement.where(operation_key: expected.map(&:first)).index_by(&:operation_key)
      return unless expected.all? do |key, folio, value|
        movement = movements[key]
        movement&.movement_type == "apply" && movement.deposit_id == @deposit.id &&
          movement.booking_folio_id == folio.id && movement.amount == value
      end

      expected.map { |key,| movements.fetch(key) }
    end

    def application_plan
      case @strategy
      when "manual"
        @folios.index_with { |folio| @manual_amounts.fetch(folio.id.to_s, 0).to_d }
      when "outstanding_balance"
        sequential_plan
      when "proportional"
        proportional_plan
      end
    end

    def sequential_plan
      remaining = @amount
      @folios.index_with do |folio|
        value = [ folio.outstanding_balance.to_d.clamp(0, remaining), remaining ].min
        remaining -= value
        value
      end
    end

    def proportional_plan
      weights = @folios.index_with { |folio| [ folio.outstanding_balance.to_d, 0.to_d ].max }
      total = weights.values.sum
      return @folios.index_with { 0.to_d } if total.zero?

      remaining = @amount
      @folios.each_with_index.to_h do |folio, index|
        value = index == @folios.length - 1 ? remaining : ((@amount * weights.fetch(folio)) / total).round(2).clamp(0, remaining)
        remaining -= value
        [ folio, value ]
      end
    end

    def failure(message)
      Deposits::BatchResult.failure(message, movements: [])
    end
  end
end
