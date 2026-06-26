# frozen_string_literal: true

require "ostruct"

module Folios
  class ReverseTransaction
    def self.call(transaction:, user:, correction_reason:, correction_note:, posting_date: nil, options: {})
      new(
        transaction: transaction,
        user: user,
        correction_reason: correction_reason,
        correction_note: correction_note,
        posting_date: posting_date,
        options: options
      ).call
    end

    def initialize(transaction:, user:, correction_reason:, correction_note:, posting_date:, options: {})
      @transaction = transaction
      @folio = transaction.booking_folio
      @user = user
      @correction_reason = correction_reason.to_s.strip
      @correction_note = correction_note.to_s.strip
      @posting_date = posting_date || @folio.hotel.current_business_date || @folio.hotel.business_date_for(Time.current)
      @options = options
    end

    def call
      return failure("Correction reason can't be blank.") if @correction_reason.blank?
      return failure("Correction note can't be blank.") if @correction_note.blank?

      policy = Folios::TransactionActionPolicy.new(transaction: @transaction, user: @user, posting_date: @posting_date)
      return failure(policy.reverse_error) unless policy.reverse_allowed?

      failure_result = nil
      reversal_transactions = []
      ActiveRecord::Base.transaction do
        originals = reversal_group.lock.to_a
        originals.each(&:lock!)

        originals.each do |original|
          original_policy = Folios::TransactionActionPolicy.new(transaction: original, user: @user, posting_date: @posting_date)
          unless original == @transaction || original_policy.generated_tax_child?
            failure_result = failure(original_policy.reverse_error)
            raise ActiveRecord::Rollback
          end

          if original.voided_by_transaction_id.present?
            failure_result = failure("Transaction has already been reversed.")
            raise ActiveRecord::Rollback
          end

          if original.reversal_of_transaction_id.present?
            failure_result = failure("Reversal transactions cannot be reversed.")
            raise ActiveRecord::Rollback
          end

          result = reverse_one(original, policy)
          unless result.success?
            failure_result = result
            raise ActiveRecord::Rollback
          end

          original.update!(voided_by_transaction: result.transaction)
          reversal_transactions << result.transaction
          reconcile_forecast_after_reversal!(original)
        end
      end

      return failure_result if failure_result

      success(reversal_transactions.first, reversal_transactions)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def reversal_group
      children = policy_for_transaction.generated_tax_children
      return FolioTransaction.where(id: @transaction.id) unless children.any?

      FolioTransaction.where(id: [ @transaction.id ] + children.map(&:id)).order(:posting_date, :created_at, :id)
    end

    def reverse_one(original, policy)
      Folios::InsertTransaction.new(
        booking_folio: original.booking_folio,
        amount: reversal_amount(original),
        transaction_type: reversal_transaction_type(original),
        category: reversal_category(original),
        user: @user,
        description: reversal_description(original),
        posting_date: @posting_date,
        options: merged_options(original, policy)
      ).call
    end

    def reversal_amount(original)
      -original.amount
    end

    def reversal_transaction_type(original)
      return "payment" if original.payment? && original.amount.positive?

      "adjustment"
    end

    def reversal_category(original)
      return "refund" if original.payment? && original.amount.positive?

      "correction"
    end

    def reversal_description(original)
      "Reversal of transaction ##{original.id}: #{@correction_reason}"
    end

    def merged_options(original, policy)
      metadata = (@options[:metadata] || {}).merge(
        posting_source: "reversal",
        reversed_transaction_id: original.id,
        reversal_group_parent_id: @transaction.id,
        posted_by_user_id: @user&.id
      )

      @options.merge(
        metadata: metadata,
        reversal_of_transaction: original,
        correction_reason: @correction_reason,
        correction_note: @correction_note,
        currency: @options[:currency] || original.currency || @folio.booking.currency
      )
        .merge(policy.override_options(correction_reason: @correction_reason, correction_note: @correction_note))
    end

    def policy_for_transaction
      @policy_for_transaction ||= Folios::TransactionActionPolicy.new(transaction: @transaction, user: @user, posting_date: @posting_date)
    end

    def reconcile_forecast_after_reversal!(original)
      return unless nightly_charge_transaction?(original)

      forecast = original.booking_folio.folio_forecasted_charges.actualized.find_by(
        stay_date: nightly_metadata(original).fetch("stay_date").to_date,
        charge_kind: nightly_metadata(original).fetch("charge_kind"),
        identity: nightly_metadata(original).fetch("forecast_identity"),
        actualizing_transaction: original
      )
      return unless forecast

      forecast.supersede!
      Folios::SyncForecastedCharges.call(booking_folio: original.booking_folio)
    end

    def nightly_charge_transaction?(original)
      original.charge? &&
        nightly_metadata(original)["nightly_charge_key"].present? &&
        nightly_metadata(original)["stay_date"].present? &&
        nightly_metadata(original)["charge_kind"].present? &&
        nightly_metadata(original)["forecast_identity"].present?
    end

    def nightly_metadata(original)
      original.metadata.to_h
    end

    def success(transaction, transactions = [ transaction ])
      OpenStruct.new(success?: true, transaction: transaction, transactions: transactions)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
