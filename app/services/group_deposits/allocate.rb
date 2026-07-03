# frozen_string_literal: true

require "ostruct"

module GroupDeposits
  class Allocate
    def self.call(deposit:, booking_folio:, amount:, actor: nil)
      new(deposit: deposit, booking_folio: booking_folio, amount: amount, actor: actor).call
    end

    def initialize(deposit:, booking_folio:, amount:, actor: nil)
      @deposit = deposit
      @folio = booking_folio
      @amount = amount.to_d
      @actor = actor
    end

    def call
      allocation = nil
      @deposit.with_lock do
        @deposit.reload
        error = validation_error
        return failure(error) if error

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: @amount,
          transaction_type: "payment",
          category: "booking_payment",
          user: @actor,
          description: "Group deposit allocation #{@deposit.id}",
          options: {
            system_posting: true,
            posting_source: "group_deposit_allocation",
            metadata: { group_deposit_id: @deposit.id }
          }
        ).call
        return failure(result.error) unless result.success?

        allocation = @deposit.group_deposit_allocations.create!(
          booking: @folio.booking,
          booking_folio: @folio,
          folio_transaction: result.transaction,
          allocated_by: @actor,
          amount: @amount,
          allocated_at: Time.current,
          status: "active"
        )
        update_deposit_status!
      end

      OpenStruct.new(success?: true, allocation: allocation)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validation_error
      return "Allocation amount must be positive." unless @amount.positive?
      return "Allocation exceeds the available group deposit." if @amount > @deposit.available_amount
      return "Folio booking must belong to the deposit group." unless @folio.booking.group_booking_id == @deposit.group_booking_id
      return "Folio currency must match the deposit currency." unless @folio.currency == @deposit.currency
      if @deposit.hotel_corporate_account_id.present? && @folio.hotel_corporate_account_id != @deposit.hotel_corporate_account_id
        return "Corporate deposit can only be allocated to folios for the same payer."
      end

      nil
    end

    def update_deposit_status!
      status = @deposit.available_amount.zero? ? "allocated" : "partially_allocated"
      @deposit.update!(status: status)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, allocation: nil)
    end
  end
end
