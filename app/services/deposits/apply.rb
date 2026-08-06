# frozen_string_literal: true

module Deposits
  class Apply
    def self.call(deposit:, booking_folio:, amount:, actor: nil, reason: nil, operation_key: nil, posting_date: nil,
      override_night_audit: false, override_reason: nil, metadata: {})
      new(deposit:, booking_folio:, amount:, actor:, reason:, operation_key:, posting_date:,
        override_night_audit:, override_reason:, metadata:).call
    end

    def initialize(deposit:, booking_folio:, amount:, actor:, reason:, operation_key:, posting_date:,
      override_night_audit:, override_reason:, metadata:)
      @deposit = deposit
      @folio = booking_folio
      @amount = amount.to_d
      @actor = actor
      @reason = reason.to_s.strip.presence
      @operation_key = operation_key.to_s.presence
      @posting_date = posting_date
      @override_night_audit = ActiveModel::Type::Boolean.new.cast(override_night_audit)
      @override_reason = override_reason.to_s.strip.presence
      @metadata = metadata.to_h
    end

    def call
      existing = existing_movement
      return success(existing) if existing

      movement = nil
      @deposit.with_lock do
        @deposit.reload
        error = validation_error
        return failure(error) if error

        category = @deposit.kind_security? ? "security_deposit" : "booking_payment"
        transaction_result = Folios::Transactions::InsertTransaction.new(
          booking_folio: @folio,
          amount: @amount,
          transaction_type: "payment",
          category: category,
          user: @actor,
          description: "#{@deposit.kind.humanize} deposit ##{@deposit.id} application",
          posting_date: @posting_date,
          options: {
            system_posting: true,
            posting_source: "deposit_application",
            transaction_code: @deposit.transaction_code,
            operation_key: folio_operation_key,
            override_night_audit: @override_night_audit,
            correction_reason: ("deposit_application_override" if @override_night_audit),
            correction_note: (@override_reason if @override_night_audit),
             metadata: @metadata.merge(
               deposit_id: @deposit.id,
               deposit_kind: @deposit.kind,
               deposit_operation_key: @operation_key
             ).compact
          }
        ).call
        return failure(transaction_result.error) unless transaction_result.success?

        movement = @deposit.deposit_movements.create!(
          movement_type: "apply",
          amount: @amount,
          booking_folio: @folio,
          folio_transaction: transaction_result.transaction,
          performed_by: @actor,
          occurred_at: Time.current,
           reason: @reason,
           metadata: @metadata,
          operation_key: @operation_key
        )
        @deposit.refresh_status!
        Deposits::SyncBookingPaymentStatus.call(@folio.booking)
        Deposits::SyncBookingDepositStatus.call(@deposit.booking) if @deposit.kind_security?
      end
      success(movement)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      movement = existing_movement
      movement ? success(movement) : failure("Deposit application was already recorded.")
    end

    private

    def existing_movement
      return if @operation_key.blank?

      movement = DepositMovement.find_by(operation_key: @operation_key)
      return if movement.blank?
      return movement if movement.deposit_id == @deposit.id && movement.booking_folio_id == @folio.id && movement.amount == @amount

      nil
    end

    def validation_error
      return "Application amount must be positive." unless @amount.positive?
      return "Deposit is not available for application." unless @deposit.status.in?(%w[held available])
      return "Application exceeds the available deposit amount." if @amount > @deposit.available_amount
      return "Folio must belong to the deposit owner." unless @deposit.eligible_folio?(@folio)

      nil
    end

    def folio_operation_key
      @operation_key.present? ? "deposit:#{@operation_key}" : nil
    end

    def success(movement)
      Deposits::MovementResult.success(deposit: @deposit, movement: movement, transaction: movement&.folio_transaction)
    end

    def failure(message)
      Deposits::MovementResult.failure(message, deposit: @deposit)
    end
  end
end
