# frozen_string_literal: true

module Deposits
  class Deduct
    ALLOWED_REASON_KEYS = %w[cleaning_revenue damage_revenue misc_revenue].freeze
    Result = ApplicationResult.define(:charge_transactions, :movements)

    def self.call(deposit:, booking_folio:, amount:, transaction_code:, actor:, posting_date:, details: nil, operation_key: nil)
      new(deposit:, booking_folio:, amount:, transaction_code:, actor:, posting_date:, details:, operation_key:).call
    end

    def initialize(deposit:, booking_folio:, amount:, transaction_code:, actor:, posting_date:, details:, operation_key:)
      @deposit = deposit
      @folio = booking_folio
      @amount = amount.to_d
      @transaction_code = transaction_code
      @actor = actor
      @posting_date = posting_date
      @details = details.to_s.strip.presence
      @operation_key = operation_key.to_s.presence || SecureRandom.uuid
    end

    def call
      error = validation_error
      return failure(error) if error

      transactions = []
      movements = []
      ActiveRecord::Base.transaction(requires_new: true) do
        @deposit.lock!
        charge = post_charge
        unless charge.success?
          error = charge.error
          raise ActiveRecord::Rollback
        end

        transactions = [ charge.transaction, *Array(charge.tax_transactions) ].compact
        total = transactions.sum { |transaction| transaction.amount.to_d }
        if total > @deposit.reload.available_amount
          error = "Deduction total exceeds the available deposit amount."
          raise ActiveRecord::Rollback
        end

        transactions.group_by(&:booking_folio).sort_by { |folio,| folio.id }.each do |folio, lines|
          result = Deposits::Apply.call(
            deposit: @deposit,
            booking_folio: folio,
            amount: lines.sum { |transaction| transaction.amount.to_d },
            actor: @actor,
            reason: description,
            posting_date: @posting_date,
            operation_key: "#{@operation_key}:apply:#{folio.id}",
            metadata: {
              deposit_deduction: true,
              deposit_reason_code: @transaction_code.code,
              source_charge_transaction_ids: lines.map(&:id)
            }
          )
          unless result.success?
            error = result.error
            raise ActiveRecord::Rollback
          end
          movements << result.movement
        end
      end

      error ? failure(error) : Result.success(charge_transactions: transactions, movements: movements)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validation_error
      return "Only security deposits can be applied as checkout deductions." unless @deposit.kind_security?
      return "Deduction amount must be positive." unless @amount.positive?
      return "Deposit is not available for application." unless @deposit.status.in?(%w[held available]) && @deposit.available_amount.positive?
      return "Selected folio is not eligible for this deposit." unless @deposit.eligible_folio?(@folio)
      return "Select a valid deposit deduction reason." unless @transaction_code&.active? && @transaction_code.kind == "charge" && @transaction_code.system_key.in?(ALLOWED_REASON_KEYS)
      return "Miscellaneous deduction details can't be blank." if @transaction_code.system_key == "misc_revenue" && @details.blank?

      nil
    end

    def post_charge
      Folios::Transactions::PostStaffTransaction.call(
        folio: @folio,
        user: @actor,
        transaction_type: "charge",
        category: @transaction_code.category,
        amount: @amount,
        description: description,
        posting_date: @posting_date,
        transaction_code_id: @transaction_code.id,
        options: {
          require_transaction_code: true,
          posting_source: "checkout_deposit_deduction",
          operation_key: "#{@operation_key}:charge",
          metadata: {
            deposit_id: @deposit.id,
            deposit_deduction: true,
            deposit_reason_code: @transaction_code.code
          }
        }
      )
    end

    def description
      @details.presence || @transaction_code.name
    end

    def failure(error)
      Result.failure(error, charge_transactions: [], movements: [])
    end
  end
end
