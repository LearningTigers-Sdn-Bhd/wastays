# frozen_string_literal: true

require "ostruct"
require "securerandom"

module Folios
  class MoveTransaction
    PERMISSION = "manage_folio_movements"

    def self.call(transaction:, target_folio:, user:, reason:, posting_date: nil)
      new(transaction: transaction, target_folio: target_folio, user: user, reason: reason, posting_date: posting_date).call
    end

    def initialize(transaction:, target_folio:, user:, reason:, posting_date: nil)
      @transaction = transaction
      @source_folio = transaction.booking_folio
      @target_folio = target_folio
      @booking = @source_folio.booking
      @hotel = @source_folio.hotel
      @user = user
      @reason = reason.to_s.strip
      @posting_date = posting_date || @hotel.current_business_date
      @operation_key = SecureRandom.uuid
      @transfer_group_id = SecureRandom.uuid
      @created_transactions = []
      @reversal_transactions = []
    end

    def call
      error = validate
      return failure(error) if error.present?

      ActiveRecord::Base.transaction do
        lock_folios!
        originals.each(&:lock!)
        reverse_originals!
        repost_to_target!
        log_operation!
      end

      success(@created_transactions)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate
      return "You do not have permission to move folio transactions." unless permitted?
      return "Move reason can't be blank." if @reason.blank?
      return "Only posted charge transactions can be moved in this phase." unless @transaction.charge?
      return "Generated tax rows move with their parent charge." if generated_tax_child?(@transaction)
      return "Source and target folios must be different." if @source_folio.id == @target_folio.id
      return "Source and target folios must belong to the same booking." unless @target_folio.booking_id == @booking.id
      return "Source and target folios must belong to the same hotel." unless @target_folio.hotel_id == @hotel.id
      return "Source folio must be open." unless @source_folio.open?
      return "Target folio must be open." unless @target_folio.open?
      return "Transaction has already been reversed." if originals.any? { |transaction| transaction.voided_by_transaction_id.present? }
      return "Reversal transactions cannot be moved." if originals.any? { |transaction| transaction.reversal_of_transaction_id.present? }

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

    def reverse_originals!
      originals.each do |original|
        result = Folios::InsertTransaction.new(
          booking_folio: @source_folio,
          amount: -original.amount,
          transaction_type: "adjustment",
          category: "correction",
          user: @user,
          description: "Move reversal of transaction ##{original.id}: #{@reason}",
          posting_date: @posting_date,
          options: movement_options(original).merge(
            reversal_of_transaction: original,
            correction_reason: "move_transaction",
            correction_note: @reason,
            metadata: movement_metadata(original).merge(reversed_transaction_id: original.id)
          )
        ).call

        raise result.error unless result.success?

        original.update!(voided_by_transaction: result.transaction)
        @reversal_transactions << result.transaction
      end
    end

    def repost_to_target!
      parent_map = {}

      originals.each do |original|
        parent = original == @transaction ? nil : parent_map[parent_id_for(original)]
        result = Folios::InsertTransaction.new(
          booking_folio: @target_folio,
          amount: original.amount,
          transaction_type: original.transaction_type,
          category: original.category,
          user: @user,
          description: original.description,
          posting_date: @posting_date,
          options: movement_options(original).merge(
            transaction_code: original.transaction_code,
            moved_from_transaction: original,
            parent_transaction: parent,
            metadata: moved_metadata(original, parent)
          )
        ).call

        raise result.error unless result.success?

        parent_map[original.id] = result.transaction
        @created_transactions << result.transaction
      end
    end

    def movement_options(original)
      {
        system_posting: true,
        posting_source: "folio_movement",
        currency: original.currency,
        transfer_group_id: @transfer_group_id,
        operation_key: @operation_key
      }
    end

    def movement_metadata(original)
      original.metadata.to_h.deep_dup.merge(
        posting_source: "folio_movement",
        operation_key: @operation_key,
        transfer_group_id: @transfer_group_id,
        folio_operation: "move_transaction",
        movement_reason: @reason,
        source_folio_id: @source_folio.id,
        target_folio_id: @target_folio.id,
        moved_from_transaction_id: original.id,
        posted_by_user_id: @user&.id
      )
    end

    def moved_metadata(original, parent)
      metadata = movement_metadata(original)
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
        operation_type: "move_transaction",
        source_folio: @source_folio,
        target_folio: @target_folio,
        source_transaction: @transaction,
        target_transaction: @created_transactions.first,
        amount: originals.sum { |transaction| transaction.amount.to_d },
        currency: @transaction.currency,
        operation_key: @operation_key,
        reason: @reason,
        metadata: {
          transfer_group_id: @transfer_group_id,
          original_transaction_ids: originals.map(&:id),
          reversal_transaction_ids: @reversal_transactions.map(&:id),
          target_transaction_ids: @created_transactions.map(&:id)
        }
      )
    end

    def permitted?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(transactions)
      OpenStruct.new(success?: true, transactions: transactions, transaction: transactions.first, operation_key: @operation_key)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, transactions: [], transaction: nil)
    end
  end
end
