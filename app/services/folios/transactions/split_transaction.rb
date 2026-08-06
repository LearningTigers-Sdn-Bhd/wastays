# frozen_string_literal: true

require "securerandom"

module Folios
  module Transactions
    class SplitTransaction
      include Authorizable

      PERMISSION = "manage_folio_movements"

      def self.call(transaction:, target_folio:, user:, reason:, amount: nil, percent: nil, posting_date: nil)
        new(transaction: transaction, target_folio: target_folio, user: user, reason: reason, amount: amount, percent: percent, posting_date: posting_date).call
      end

      def initialize(transaction:, target_folio:, user:, reason:, amount: nil, percent: nil, posting_date: nil)
        @transaction = transaction
        @source_folio = transaction.booking_folio
        @target_folio = target_folio
        @booking = @source_folio.booking
        @hotel = @source_folio.hotel
        @user = user
        @reason = reason.to_s.strip
        @amount = amount.presence&.to_d
        @percent = percent.presence&.to_d
        @posting_date = posting_date || @hotel.current_business_date
        @operation_key = SecureRandom.uuid
        @transfer_group_id = SecureRandom.uuid
        @source_transactions = []
        @target_transactions = []
        @reversal_transactions = []
      end

      def call
        error = validate
        return failure(error) if error.present?

        ActiveRecord::Base.transaction do
          lock_folios!
          originals.each(&:lock!)
          reverse_originals!
          repost_split_rows!
          log_operation!
        end

        success(@source_transactions, @target_transactions)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        failure(e.message)
      end

      private

      def validate
        return "You do not have permission to split folio transactions." unless permitted?
        return "Split reason can't be blank." if @reason.blank?
        return "Only posted charge transactions can be split in this phase." unless @transaction.charge?
        return "Generated tax rows split with their parent charge." if generated_tax_child?(@transaction)
        return "Source and target folios must be different." if @source_folio.id == @target_folio.id
        return "Source and target folios must belong to the same booking." unless @target_folio.booking_id == @booking.id
        return "Source and target folios must belong to the same hotel." unless @target_folio.hotel_id == @hotel.id
        return "Source folio must be open." unless @source_folio.open?
        return "Target folio must be open." unless @target_folio.open?
        return "Transaction has already been reversed." if originals.any? { |transaction| transaction.voided_by_transaction_id.present? }
        return "Reversal transactions cannot be split." if originals.any? { |transaction| transaction.reversal_of_transaction_id.present? }
        return "Provide either split amount or percent, not both." if @amount.present? && @percent.present?
        return "Split amount or percent is required." if @amount.blank? && @percent.blank?
        return "Split amount must be greater than zero." unless target_parent_amount.positive?
        return "Split amount must be less than the source transaction amount." if target_parent_amount >= @transaction.amount.to_d

        nil
      end

      def lock_folios!
        [ @source_folio, @target_folio ].sort_by(&:id).each(&:lock!)
      end

      def originals
        @originals ||= begin
          children = generated_tax_children(@transaction).to_a
          [ @transaction, *children ].sort_by { |transaction| [ transaction.posting_date, transaction.created_at, transaction.id ] }
        end
      end

      def target_parent_amount
        @target_parent_amount ||= begin
          if @percent.present?
            (@transaction.amount.to_d * (@percent / 100)).round(2)
          else
            @amount.to_d.round(2)
          end
        end
      end

      def split_ratio
        @split_ratio ||= target_parent_amount / @transaction.amount.to_d
      end

      def reverse_originals!
        originals.each do |original|
          result = Folios::Transactions::InsertTransaction.new(
            booking_folio: @source_folio,
            amount: -original.amount,
            transaction_type: "adjustment",
            category: "correction",
            user: @user,
            description: "Split reversal of transaction ##{original.id}: #{@reason}",
            posting_date: @posting_date,
            options: split_options(original).merge(
              reversal_of_transaction: original,
              correction_reason: "split_transaction",
              correction_note: @reason,
              metadata: reversal_metadata(original).merge(reversed_transaction_id: original.id)
            )
          ).call

          raise result.error unless result.success?

          original.update!(voided_by_transaction: result.transaction)
          @reversal_transactions << result.transaction
        end
      end

      def repost_split_rows!
        source_parent_map = {}
        target_parent_map = {}

        originals.each do |original|
          source_amount, target_amount = split_amounts_for(original)
          source_parent = original == @transaction ? nil : source_parent_map[parent_id_for(original)]
          target_parent = original == @transaction ? nil : target_parent_map[parent_id_for(original)]

          source_result = post_split_row(
            folio: @source_folio,
            original: original,
            amount: source_amount,
            parent: source_parent,
            side: "source_remainder"
          )
          target_result = post_split_row(
            folio: @target_folio,
            original: original,
            amount: target_amount,
            parent: target_parent,
            side: "target_split"
          )

          source_parent_map[original.id] = source_result.transaction
          target_parent_map[original.id] = target_result.transaction
          @source_transactions << source_result.transaction
          @target_transactions << target_result.transaction
        end
      end

      def post_split_row(folio:, original:, amount:, parent:, side:)
        result = Folios::Transactions::InsertTransaction.new(
          booking_folio: folio,
          amount: amount,
          transaction_type: original.transaction_type,
          category: original.category,
          user: @user,
          description: original.description,
          posting_date: @posting_date,
          options: split_options(original).merge(
            transaction_code: original.transaction_code,
            split_from_transaction: original,
            parent_transaction: parent,
            metadata: split_row_metadata(original, parent, side)
          )
        ).call

        raise result.error unless result.success?

        result
      end

      def split_amounts_for(original)
        target_amount = if original == @transaction
          target_parent_amount
        else
          (original.amount.to_d * split_ratio).round(2)
        end
        source_amount = original.amount.to_d - target_amount
        [ source_amount, target_amount ]
      end

      def split_options(original)
        {
          system_posting: true,
          posting_source: "folio_split",
          currency: original.currency,
          transfer_group_id: @transfer_group_id,
          operation_key: @operation_key
        }
      end

      def split_metadata(original)
        original.metadata.to_h.deep_dup.merge(
          posting_source: "folio_split",
          operation_key: @operation_key,
          transfer_group_id: @transfer_group_id,
          folio_operation: "split_transaction",
          split_reason: @reason,
          source_folio_id: @source_folio.id,
          target_folio_id: @target_folio.id,
          split_from_transaction_id: original.id,
          split_ratio: split_ratio.to_s("F"),
          posted_by_user_id: @user&.id
        )
      end

      def reversal_metadata(original)
        split_metadata(original).except(
          "nightly_charge_key",
          :nightly_charge_key,
          "reconciles_nightly_charge_key",
          :reconciles_nightly_charge_key,
          "catch_up_key",
          :catch_up_key
        )
      end

      def split_row_metadata(original, parent, side)
        metadata = split_metadata(original).merge(split_side: side)
        if parent.present?
          metadata["parent_folio_transaction_id"] = parent.id
          metadata[:parent_folio_transaction_id] = parent.id
        end
        metadata
      end

      def generated_tax_child?(transaction)
        metadata = transaction.metadata.to_h
        metadata["parent_folio_transaction_id"].present? || metadata["tax_line"].present?
      end

      def generated_tax_children(transaction)
        transaction.booking_folio.folio_transactions
          .where("metadata->>'parent_folio_transaction_id' = ?", transaction.id.to_s)
          .order(:posting_date, :created_at, :id)
      end

      def parent_id_for(transaction)
        transaction.metadata.to_h["parent_folio_transaction_id"].to_i
      end

      def log_operation!
        FolioOperationLog.create!(
          hotel: @hotel,
          booking: @booking,
          actor: @user,
          operation_type: "split_transaction",
          source_folio: @source_folio,
          target_folio: @target_folio,
          source_transaction: @transaction,
          target_transaction: @target_transactions.first,
          amount: target_parent_amount,
          currency: @transaction.currency,
          operation_key: @operation_key,
          reason: @reason,
          metadata: {
            transfer_group_id: @transfer_group_id,
            split_ratio: split_ratio.to_s("F"),
            original_transaction_ids: originals.map(&:id),
            reversal_transaction_ids: @reversal_transactions.map(&:id),
            source_transaction_ids: @source_transactions.map(&:id),
            target_transaction_ids: @target_transactions.map(&:id)
          }
        )
      end

      def permitted?
        actor_permits?(@user, PERMISSION, hotel: @hotel)
      end

      def success(source_transactions, target_transactions)
        Folios::Transactions::SplitResult.success(
          source_transactions: source_transactions,
          target_transactions: target_transactions,
          transaction: target_transactions.first,
          operation_key: @operation_key
        )
      end

      def failure(error)
        Folios::Transactions::SplitResult.failure(error, source_transactions: [], target_transactions: [])
      end
    end
  end
end
