# frozen_string_literal: true

require "ostruct"

module GroupDeposits
  class AllocateAcrossFolios
    STRATEGIES = %w[manual proportional outstanding_balance].freeze

    def self.call(deposit:, folios:, amount:, strategy:, actor: nil, manual_amounts: {})
      new(deposit: deposit, folios: folios, amount: amount, strategy: strategy, actor: actor, manual_amounts: manual_amounts).call
    end

    def initialize(deposit:, folios:, amount:, strategy:, actor:, manual_amounts:)
      @deposit = deposit
      @folios = Array(folios).uniq
      @amount = amount.to_d
      @strategy = strategy.to_s
      @actor = actor
      @manual_amounts = manual_amounts.to_h.transform_keys(&:to_s)
    end

    def call
      return failure("Unknown allocation strategy.") unless @strategy.in?(STRATEGIES)
      return failure("Select at least one folio.") if @folios.empty?
      return failure("Allocation exceeds the available group deposit.") if @amount > @deposit.available_amount

      plan = allocation_plan
      return failure("Allocation plan must equal the requested amount.") unless plan.values.sum == @amount

      allocations = []
      GroupDepositAllocation.transaction do
        plan.each do |folio, value|
          next unless value.positive?

          result = GroupDeposits::Allocate.call(deposit: @deposit, booking_folio: folio, amount: value, actor: @actor)
          raise result.error unless result.success?
          allocations << result.allocation
        end
      end
      OpenStruct.new(success?: true, allocations: allocations)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def allocation_plan
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
        value = if index == @folios.length - 1
                  remaining
        else
                  ((@amount * weights.fetch(folio)) / total).round(2).clamp(0, remaining)
        end
        remaining -= value
        [ folio, value ]
      end
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, allocations: [])
    end
  end
end
