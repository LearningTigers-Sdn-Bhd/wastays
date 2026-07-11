# frozen_string_literal: true

require "ostruct"

module GroupDeposits
  class ReverseAllocation
    def self.call(allocation:, actor:, reason:)
      new(allocation: allocation, actor: actor, reason: reason).call
    end

    def initialize(allocation:, actor:, reason:)
      @allocation = allocation
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      return failure("Reason can't be blank.") if @reason.blank?
      return failure("Allocation has already been reversed.") unless @allocation.status == "active"

      reversal = nil
      @allocation.group_deposit.with_lock do
        result = Folios::ReverseTransaction.call(
          transaction: @allocation.folio_transaction,
          user: @actor,
          correction_reason: "group_deposit_allocation_reversal",
          correction_note: @reason,
          options: { metadata: { group_deposit_allocation_id: @allocation.id } }
        )
        return failure(result.error) unless result.success?

        @allocation.update!(status: "reversed", reversed_at: Time.current)
        reversal = @allocation.group_deposit.group_deposit_allocations.create!(
          booking: @allocation.booking,
          booking_folio: @allocation.booking_folio,
          folio_transaction: result.transaction,
          allocated_by: @actor,
          reversal_of: @allocation,
          amount: @allocation.amount,
          allocated_at: Time.current,
          reversed_at: Time.current,
          status: "reversed",
          metadata: { reason: @reason }
        )
        refresh_deposit_status!
      end

      OpenStruct.new(success?: true, reversal: reversal)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def refresh_deposit_status!
      deposit = @allocation.group_deposit
      status = deposit.allocated_amount.zero? ? "received" : "partially_allocated"
      deposit.update!(status: status)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, reversal: nil)
    end
  end
end
