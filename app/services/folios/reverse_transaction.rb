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
      @posting_date = posting_date || @folio.hotel.current_business_date
      @options = options
    end

    def call
      return failure("Correction reason can't be blank.") if @correction_reason.blank?
      return failure("Correction note can't be blank.") if @correction_note.blank?

      ActiveRecord::Base.transaction do
        @transaction.lock!

        return failure("Transaction has already been reversed.") if @transaction.voided_by_transaction_id.present?
        return failure("Reversal transactions cannot be reversed.") if @transaction.reversal_of_transaction_id.present?

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: reversal_amount,
          transaction_type: reversal_transaction_type,
          category: reversal_category,
          user: @user,
          description: reversal_description,
          posting_date: @posting_date,
          options: merged_options
        ).call

        return result unless result.success?

        @transaction.update!(voided_by_transaction: result.transaction)
        reconcile_forecast_after_reversal!
        success(result.transaction)
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def reversal_amount
      -@transaction.amount
    end

    def reversal_transaction_type
      return "payment" if @transaction.payment? && @transaction.amount.positive?

      "adjustment"
    end

    def reversal_category
      return "refund" if @transaction.payment? && @transaction.amount.positive?

      "correction"
    end

    def reversal_description
      "Reversal of transaction ##{@transaction.id}: #{@correction_reason}"
    end

    def merged_options
      metadata = (@options[:metadata] || {}).merge(
        posting_source: "reversal",
        reversed_transaction_id: @transaction.id,
        posted_by_user_id: @user&.id
      )

      @options.merge(
        metadata: metadata,
        reversal_of_transaction: @transaction,
        correction_reason: @correction_reason,
        correction_note: @correction_note,
        currency: @options[:currency] || @transaction.currency || @folio.booking.currency
      )
    end

    def reconcile_forecast_after_reversal!
      return unless nightly_charge_transaction?

      forecast = @folio.folio_forecasted_charges.actualized.find_by(
        stay_date: nightly_metadata.fetch("stay_date").to_date,
        charge_kind: nightly_metadata.fetch("charge_kind"),
        identity: nightly_metadata.fetch("forecast_identity"),
        actualizing_transaction: @transaction
      )
      return unless forecast

      forecast.supersede!
      Folios::SyncForecastedCharges.call(booking_folio: @folio)
    end

    def nightly_charge_transaction?
      @transaction.charge? &&
        nightly_metadata["nightly_charge_key"].present? &&
        nightly_metadata["stay_date"].present? &&
        nightly_metadata["charge_kind"].present? &&
        nightly_metadata["forecast_identity"].present?
    end

    def nightly_metadata
      @nightly_metadata ||= @transaction.metadata.to_h
    end

    def success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
