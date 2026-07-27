# frozen_string_literal: true

module Deposits
  class Return
    def self.call(deposit:, amount:, actor: nil, payment_method: nil, external_reference: nil, reason: nil,
      operation_key: nil, occurred_at: nil)
      new(deposit:, amount:, actor:, payment_method:, external_reference:, reason:, operation_key:, occurred_at:).call
    end

    def initialize(deposit:, amount:, actor:, payment_method:, external_reference:, reason:, operation_key:, occurred_at:)
      @deposit = deposit
      @amount = amount.to_d
      @actor = actor
      @payment_method = payment_method.to_s.presence || deposit.payment_method
      @external_reference = external_reference.to_s.strip.presence
      @reason = reason.to_s.strip.presence
      @operation_key = operation_key.to_s.presence
      @occurred_at = occurred_at
    end

    def call
      existing = DepositMovement.find_by(operation_key: @operation_key) if @operation_key
      return success(existing) if matching_retry?(existing)

      movement = nil
      @deposit.with_lock do
        @deposit.reload
        return failure("Return amount must be positive.") unless @amount.positive?
        return failure("Deposit is not available for return.") unless @deposit.status.in?(%w[held available])
        return failure("Return exceeds the available deposit amount.") if @amount > @deposit.available_amount
        return failure("Reason can't be blank.") if @deposit.kind_prepayment? && @reason.blank?

        movement = @deposit.deposit_movements.create!(
          movement_type: @deposit.kind_security? ? "release" : "refund",
          amount: @amount,
          performed_by: @actor,
          payment_method: @payment_method,
          external_reference: @external_reference,
          reason: @reason,
          occurred_at: @occurred_at || Time.current,
          operation_key: @operation_key
        )
        @deposit.refresh_status!
        sync_booking_deposit_status!
      end
      success(movement)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      existing = DepositMovement.find_by(operation_key: @operation_key) if @operation_key
      matching_retry?(existing) ? success(existing) : failure("Deposit return was already recorded.")
    end

    private

    def matching_retry?(movement)
      movement.present? && movement.deposit_id == @deposit.id && movement.amount == @amount &&
        movement.movement_type == (@deposit.kind_security? ? "release" : "refund")
    end

    def sync_booking_deposit_status!
      return unless @deposit.kind_security? && @deposit.booking.present?

      status = @deposit.booking.deposits.kind_security.where(status: "held").exists? ? "held" : "released"
      @deposit.booking.update!(deposit_status: status)
    end

    def success(movement)
      Deposits::MovementResult.success(deposit: @deposit, movement: movement, transaction: nil)
    end

    def failure(message)
      Deposits::MovementResult.failure(message, deposit: @deposit)
    end
  end
end
