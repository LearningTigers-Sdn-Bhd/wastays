# frozen_string_literal: true

module Folios
  module Payments
    class ReallocatePayment
      include Authorizable
      include Folios::MovementLocking

      def self.call(transaction:, target_folio:, user:, reason:, amount:, posting_date: nil, operation_key: nil)
        new(transaction:, target_folio:, user:, reason:, amount:, posting_date:, operation_key:).call
      end

      def initialize(transaction:, target_folio:, user:, reason:, amount:, posting_date:, operation_key:)
        @transaction = transaction
        @source = transaction.booking_folio
        @target = target_folio
        @user = user
        @reason = reason.to_s.strip
        @amount = amount.to_d.round(2)
        @date = posting_date || @source.hotel.current_business_date
        @key = operation_key || SecureRandom.uuid
        @source_rows = []
        @target_rows = []
      end

      def call
        ActiveRecord::Base.transaction do
          lock_movement!(folios: [ @source, @target ], transactions: [ @transaction ])
          error = validation_error
          return failure(error) if error

          if @transaction.metadata["deposit_id"].present?
            reallocate_deposit!
          else
            reversal = post!(@source, -@transaction.amount, reversal_of_transaction: @transaction)
            @transaction.update!(voided_by_transaction: reversal)
            @source_rows << post!(@source, @transaction.amount - @amount, split_from_transaction: @transaction) if @amount < @transaction.amount
            lineage = @amount < @transaction.amount ? { split_from_transaction: @transaction } : { moved_from_transaction: @transaction }
            @target_rows << post!(@target, @amount, **lineage)
          end
          log_operation!
          Deposits::SyncBookingPaymentStatus.call(@transaction.source_booking, folio_transaction: @target_rows.first, user: @user)
        end
        Folios::Transactions::SplitResult.success(transaction: @target_rows.first, source_transactions: @source_rows,
          target_transactions: @target_rows, operation_key: @key)
      rescue StandardError => e
        failure(e.message)
      end

      private

      def validation_error
        return "You do not have permission to move folio transactions." unless actor_permits?(@user, "manage_folio_movements", hotel: @source.hotel)
        return "Only supported payment entries can be reallocated." unless @transaction.payment?
        return "Reason can't be blank." if @reason.blank?
        return "Source and target folios must be different." if @source.id == @target.id
        error = Folios::Transactions::MovementPolicy.error(@transaction) || Folios::DestinationPolicy.error(booking: @source.booking, folio: @target)
        return error if error
        "Split amount must be greater than zero and no more than the payment." unless @amount.positive? && @amount <= @transaction.amount
      end

      def metadata
        @transaction.metadata.deep_dup.except("payment_transaction_id").merge("original_payment_transaction_id" => (@transaction.metadata["payment_transaction_id"] || @transaction.metadata["original_payment_transaction_id"]), "internal_folio_movement" => true, "receipt_policy" => "none",
          "posting_source" => "folio_payment_reallocation", "operation_key" => @key,
          "source_folio_id" => @source.id, "target_folio_id" => @target.id, "movement_reason" => @reason)
      end

      def post!(folio, amount, **lineage)
        result = Folios::Transactions::InsertTransaction.new(booking_folio: folio, amount:,
          transaction_type: "payment", category: amount.negative? ? "refund" : @transaction.category, user: @user,
          description: amount.negative? ? "Payment allocation reversal: #{@reason}" : @transaction.description,
          posting_date: @date, options: lineage.merge(system_posting: true, source_booking: @transaction.source_booking,
            currency: @transaction.currency, transaction_code: @transaction.transaction_code, operation_key: @key,
            transaction_code_code_snapshot: @transaction.transaction_code_code_snapshot,
            transaction_code_name_snapshot: @transaction.transaction_code_name_snapshot, gl_code: @transaction.gl_code,
            transfer_group_id: @key, metadata: metadata)).call
        raise result.error unless result.success?

        result.transaction
      end

      def reallocate_deposit!
        movement = @transaction.deposit_movement
        result = Deposits::ReverseApplication.call(movement:, actor: @user, reason: @reason,
          operation_key: "#{@key}:reverse", metadata: metadata)
        raise result.error unless result.success?

        [ [ @source, @transaction.amount - @amount, @source_rows ], [ @target, @amount, @target_rows ] ].each_with_index do |(folio, value, rows), index|
          next unless value.positive?

          result = Deposits::Apply.call(deposit: movement.deposit, booking_folio: folio, amount: value, actor: @user,
            reason: @reason, posting_date: @date, operation_key: "#{@key}:apply:#{index}",
            metadata: metadata, source_booking: @transaction.source_booking,
            lineage: @amount < @transaction.amount ? { split_from_transaction: @transaction } : { moved_from_transaction: @transaction })
          raise result.error unless result.success?

          rows << result.transaction
        end
      end

      def log_operation!
        FolioOperationLog.create!(hotel: @source.hotel, booking: @source.booking, actor: @user,
          operation_type: @amount == @transaction.amount ? "move_transaction" : "split_transaction",
          source_folio: @source, target_folio: @target, source_transaction: @transaction,
          target_transaction: @target_rows.first, amount: @amount, currency: @transaction.currency,
          reason: @reason, operation_key: @key, metadata: { internal_folio_movement: true,
            source_transaction_ids: @source_rows.map(&:id), target_transaction_ids: @target_rows.map(&:id) })
      end

      def failure(error)
        Folios::Transactions::SplitResult.failure(error, source_transactions: [], target_transactions: [])
      end
    end
  end
end
