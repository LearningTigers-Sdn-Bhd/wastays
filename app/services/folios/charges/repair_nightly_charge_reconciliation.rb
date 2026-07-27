# frozen_string_literal: true

require "securerandom"

module Folios
  module Charges
    class RepairNightlyChargeReconciliation
      Result = ApplicationResult.define(:reconciliation, :reversed_transactions, :posted_transactions, :operation_key)

      def self.call(booking:, reconciliation:, actor:, reason:, night_audit:, posting_options: {})
        new(
          booking: booking,
          reconciliation: reconciliation,
          actor: actor,
          reason: reason,
          night_audit: night_audit,
          posting_options: posting_options
        ).call
      end

      def initialize(booking:, reconciliation:, actor:, reason:, night_audit:, posting_options: {})
        @booking = booking
        @reconciliation = reconciliation
        @actor = actor
        @reason = reason.to_s.strip
        @night_audit = night_audit
        @business_date = night_audit.business_date.to_date
        @posting_options = posting_options
        @operation_key = SecureRandom.uuid
        @reversed_transactions = []
        @posted_transactions = []
      end

      def call
        return success_result if @reconciliation.valid?

        @booking.with_lock do
          ActiveRecord::Base.transaction do
            @reconciliation.entries.each { |entry| repair_entry!(entry) }
            record_operation_log!
          end
        end

        refresh_forecasts!
        success_result(reconciliation: current_reconciliation)
      rescue StandardError => e
        Result.failure(
          e.message,
          reconciliation: @reconciliation,
          reversed_transactions: [],
          posted_transactions: [],
          operation_key: @operation_key
        )
      end

      private

      def repair_entry!(entry)
        return if entry[:issues].empty?
        raise entry[:route].error unless entry[:route].success?

        canonical = entry[:valid_transactions].min_by(&:id)
        (entry[:transactions] - [ canonical ]).each { |transaction| reverse_transaction!(transaction, entry) }
        post_expected_line!(entry, moved_from: entry[:transactions].min_by(&:id)) if canonical.blank?
      end

      def reverse_transaction!(transaction, entry)
        result = Folios::Transactions::InsertTransaction.new(
          booking_folio: transaction.booking_folio,
          amount: -transaction.amount,
          transaction_type: "adjustment",
          category: "correction",
          user: @actor,
          description: "Night Audit repair reversal: #{transaction.description}",
          posting_date: @business_date,
          options: transaction_options.merge(
            reversal_of_transaction: transaction,
            metadata: repair_metadata(entry).merge(
              repair_action: "reverse",
              reversed_transaction_id: transaction.id
            )
          )
        ).call
        raise "Failed to reverse nightly charge ##{transaction.id}: #{result.error}" unless result.success?

        transaction.update!(voided_by_transaction: result.transaction)
        @reversed_transactions << result.transaction
      end

      def post_expected_line!(entry, moved_from:)
        line = entry[:line]
        metadata = expected_metadata(entry)
        if nightly_key_occupied_on_target?(entry)
          metadata[:reconciles_nightly_charge_key] = entry[:nightly_charge_key]
        else
          metadata[:nightly_charge_key] = entry[:nightly_charge_key]
        end

        result = Folios::Transactions::InsertTransaction.new(
          booking_folio: entry[:route].folio,
          amount: line[:amount],
          transaction_type: "charge",
          category: line[:category],
          user: @actor,
          description: line[:description],
          posting_date: @business_date,
          options: transaction_options.merge(
            transaction_code: line[:transaction_code],
            moved_from_transaction: moved_from,
            metadata: metadata
          )
        ).call
        raise "Failed to repost nightly charge #{entry[:nightly_charge_key]}: #{result.error}" unless result.success?

        @posted_transactions << result.transaction
      end

      def transaction_options
        @posting_options.merge(
          night_audit: @night_audit,
          correction_reason: @posting_options[:correction_reason].presence || @reason
        )
      end

      def expected_metadata(entry)
        line = entry[:line]
        repair_metadata(entry).merge(
          tax_line: line[:tax_line],
          route_source: entry[:route].route_source,
          route_metadata: entry[:route].route_metadata,
          repair_action: "repost"
        ).compact
      end

      def repair_metadata(entry)
        {
          posting_source: transaction_options[:posting_source],
          night_audit_id: @night_audit.id,
          stay_date: @business_date.iso8601,
          booking_id: @booking.id,
          charge_kind: entry[:line][:charge_kind],
          forecast_identity: entry[:line][:identity].to_s,
          blocker_resolution: transaction_options[:blocker_resolution],
          operation_key: @operation_key,
          repaired_by_user_id: @actor&.id
        }.compact
      end

      def nightly_key_occupied_on_target?(entry)
        entry[:route].folio.folio_transactions.where(
          "metadata->>'nightly_charge_key' = ?",
          entry[:nightly_charge_key]
        ).exists?
      end

      def refresh_forecasts!
        primary_folio = @booking.booking_folio
        Folios::Forecasts::SyncForecastedCharges.call(booking_folio: primary_folio) if primary_folio.present?
      end

      def current_reconciliation
        Folios::Charges::NightlyChargeReconciliation.call(
          booking: @booking.reload,
          business_date: @business_date,
          allow_closed_folio: @posting_options[:override_closed_folio]
        )
      end

      def record_operation_log!
        return if @reversed_transactions.empty? && @posted_transactions.empty?

        FolioOperationLog.create!(
          hotel: @booking.hotel,
          booking: @booking,
          actor: @actor,
          operation_type: "correction",
          source_folio: @reversed_transactions.first&.booking_folio,
          target_folio: @posted_transactions.first&.booking_folio,
          source_transaction: @reversed_transactions.first&.reversal_of_transaction,
          target_transaction: @posted_transactions.first,
          amount: @posted_transactions.sum { |transaction| transaction.amount.to_d },
          currency: @booking.currency,
          operation_key: @operation_key,
          reason: @reason,
          metadata: {
            correction_type: "nightly_charge_repair",
            posting_source: transaction_options[:posting_source],
            night_audit_id: @night_audit.id,
            business_date: @business_date.iso8601,
            reversed_transaction_ids: @reversed_transactions.map(&:id),
            posted_transaction_ids: @posted_transactions.map(&:id)
          }
        )
      end

      def success_result(reconciliation: @reconciliation)
        Result.success(
          reconciliation: reconciliation,
          reversed_transactions: @reversed_transactions,
          posted_transactions: @posted_transactions,
          operation_key: @operation_key
        )
      end
    end
  end
end
