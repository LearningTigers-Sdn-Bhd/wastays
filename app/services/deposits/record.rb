# frozen_string_literal: true

module Deposits
  class Record
    def self.call(owner:, kind:, amount:, currency:, payment_method:, actor: nil, external_reference: nil,
      hotel_corporate_account: nil, metadata: {}, status: nil, received_at: nil, operation_key: nil)
      new(owner:, kind:, amount:, currency:, payment_method:, actor:, external_reference:,
        hotel_corporate_account:, metadata:, status:, received_at:, operation_key:).call
    end

    def initialize(owner:, kind:, amount:, currency:, payment_method:, actor:, external_reference:,
      hotel_corporate_account:, metadata:, status:, received_at:, operation_key:)
      @owner = owner
      @kind = kind.to_s
      @amount = amount.to_d
      @currency = currency.to_s.presence || owner.hotel.default_currency || "MYR"
      @payment_method = payment_method.to_s.presence || "cash"
      @actor = actor
      @external_reference = external_reference.to_s.strip.presence
      @hotel_corporate_account = hotel_corporate_account
      @metadata = metadata.to_h
      @status = status.to_s.presence
      @received_at = received_at
      @operation_key = operation_key.to_s.presence
    end

    def call
      return failure("Deposit amount must be positive.") unless @amount.positive?
      return failure("Unknown deposit kind.") unless @kind.in?(Deposit::KINDS)
      return failure("Deposit owner must be a booking or group booking.") unless @owner.is_a?(Booking) || @owner.is_a?(GroupBooking)
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      deposit = nil
      Deposit.transaction do
        deposit = Deposit.create!(deposit_attributes)
        deposit.deposit_movements.create!(
          movement_type: @kind == "security" ? "hold" : "receive",
          amount: @amount,
          payment_method: @payment_method,
          external_reference: @external_reference,
          performed_by: @actor,
          occurred_at: deposit.received_at,
          operation_key: @operation_key || "deposit:#{deposit.id}:opening",
          metadata: @metadata
        )
        sync_booking_deposit_status!(deposit)
      end
      success(deposit)
    rescue ActiveRecord::RecordInvalid => e
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      failure("Deposit reference has already been used.")
    end

    private

    def existing_deposit
      if @operation_key
        movement = DepositMovement.find_by(operation_key: @operation_key)
        opening_type = @kind == "security" ? "hold" : "receive"
        movement.deposit if movement&.movement_type == opening_type && movement.amount == @amount
      elsif @external_reference
        Deposit.find_by(
          hotel: hotel,
          booking: (@owner if @owner.is_a?(Booking)),
          group_booking: (@owner if @owner.is_a?(GroupBooking)),
          external_reference: @external_reference
        )
      end
    end

    def hotel
      @owner.hotel
    end

    def deposit_attributes
      {
        hotel: hotel,
        booking: (@owner if @owner.is_a?(Booking)),
        group_booking: (@owner if @owner.is_a?(GroupBooking)),
        hotel_corporate_account: @hotel_corporate_account,
        transaction_code: transaction_code,
        received_by: @actor,
        kind: @kind,
        status: @status || (@kind == "security" ? "held" : "available"),
        amount: @amount,
        currency: @currency,
        payment_method: @payment_method,
        external_reference: @external_reference,
        received_at: @received_at || Time.current,
        metadata: @metadata
      }
    end

    def transaction_code
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      key = @kind == "security" ? "security_deposit" : "bank_payment"
      TransactionCodes::Resolver.for(hotel).for_key!(key)
    end

    def sync_booking_deposit_status!(deposit)
      return unless deposit.kind_security? && deposit.booking.present?

      Deposits::SyncBookingDepositStatus.call(deposit.booking)
    end

    def matching_retry?(deposit)
      deposit.present? && deposit.owner == @owner && deposit.kind == @kind &&
        deposit.amount == @amount && deposit.currency == @currency
    end

    def success(deposit)
      Deposits::RecordResult.success(deposit: deposit)
    end

    def failure(message)
      Deposits::RecordResult.failure(message)
    end
  end
end
