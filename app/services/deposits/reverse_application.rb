# frozen_string_literal: true

module Deposits
  class ReverseApplication
    def self.call(movement:, actor:, reason:, operation_key: nil)
      new(movement:, actor:, reason:, operation_key:).call
    end

    def initialize(movement:, actor:, reason:, operation_key:)
      @movement = movement
      @deposit = movement.deposit
      @actor = actor
      @reason = reason.to_s.strip
      @operation_key = operation_key.to_s.presence
    end

    def call
      return failure("Reason can't be blank.") if @reason.blank?
      return failure("Only deposit applications can be reversed.") unless @movement.movement_type == "apply"
      existing = existing_reversal
      return success(existing) if existing
      return failure("Application has already been reversed.") if @movement.reversal.present?

      reversal = nil
      @deposit.with_lock do
        @movement.reload
        existing = existing_reversal
        return success(existing) if existing
        return failure("Application has already been reversed.") if @movement.reversal.present?

        result = Folios::Transactions::ReverseTransaction.call(
          transaction: @movement.folio_transaction,
          user: @actor,
          correction_reason: "deposit_application_reversal",
          correction_note: @reason,
          options: {
            operation_key: @operation_key && "deposit:#{@operation_key}",
            metadata: { deposit_id: @deposit.id, deposit_movement_id: @movement.id }
          }
        )
        return failure(result.error) unless result.success?

        reversal = @deposit.deposit_movements.create!(
          movement_type: "reverse",
          amount: @movement.amount,
          booking_folio: @movement.booking_folio,
          folio_transaction: result.transaction,
          performed_by: @actor,
          reversal_of: @movement,
          reason: @reason,
          occurred_at: Time.current,
          operation_key: @operation_key
        )
        @deposit.refresh_status!
        Deposits::SyncBookingPaymentStatus.call(@movement.booking_folio.booking)
      end
      success(reversal)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      reversal = existing_reversal
      reversal ? success(reversal) : failure("Deposit application reversal was already recorded.")
    end

    private

    def existing_reversal
      return if @operation_key.blank?

      movement = DepositMovement.find_by(operation_key: @operation_key)
      return movement if movement&.movement_type == "reverse" && movement.reversal_of_id == @movement.id

      nil
    end

    def success(movement)
      Deposits::MovementResult.success(deposit: @deposit, movement: movement, transaction: movement.folio_transaction)
    end

    def failure(message)
      Deposits::MovementResult.failure(message, deposit: @deposit)
    end
  end
end
