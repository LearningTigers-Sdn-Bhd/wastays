# frozen_string_literal: true

require "ostruct"

module GroupDeposits
  class RefundUnallocated
    def self.call(deposit:, amount:, actor: nil, reason:)
      new(deposit: deposit, amount: amount, actor: actor, reason: reason).call
    end

    def initialize(deposit:, amount:, actor:, reason:)
      @deposit = deposit
      @amount = amount.to_d
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      @deposit.with_lock do
        @deposit.reload
        return failure("Refund amount must be positive.") unless @amount.positive?
        return failure("Reason can't be blank.") if @reason.blank?
        return failure("Refund exceeds the unallocated amount.") if @amount > @deposit.available_amount

        refunded_amount = @deposit.refunded_amount + @amount
        status = refunded_amount == @deposit.amount ? "refunded" : "partially_refunded"
        @deposit.update!(
          refunded_amount: refunded_amount,
          refunded_at: Time.current,
          status: status,
          metadata: @deposit.metadata.to_h.merge(
            "last_refund_reason" => @reason,
            "last_refund_actor_id" => @actor&.id
          )
        )
      end

      OpenStruct.new(success?: true, deposit: @deposit)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, error: message, deposit: nil)
    end
  end
end
