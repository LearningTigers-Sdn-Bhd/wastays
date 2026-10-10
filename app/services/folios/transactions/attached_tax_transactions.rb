# frozen_string_literal: true

module Folios
  module Transactions
    class AttachedTaxTransactions
      def self.call(transaction, candidates: nil)
        new(transaction, candidates:).call
      end

      def self.candidates_for(transactions)
        FolioTransaction.joins(:booking_folio)
          .includes(:booking_folio, :transaction_code)
          .where(source_booking_id: transactions.map(&:source_booking_id), booking_folios: { hotel_id: transactions.map { |row| row.booking_folio.hotel_id }.uniq })
          .charge.where(voided_by_transaction_id: nil)
          .where("folio_transactions.category = 'tax' OR folio_transactions.metadata ? 'tax_line'")
      end

      def initialize(transaction, candidates: nil)
        @transaction = transaction
        @folio = transaction.booking_folio
        @booking = transaction.source_booking
        @candidates = candidates
      end

      def call
        attached_scope.to_a.sort_by { |transaction| [ transaction.posting_date, transaction.created_at, transaction.id ] }
      end

      private

      def attached_scope
        tax_scope.select { |candidate| attached_by_parent?(candidate) || attached_by_tax_rule?(candidate) }
      end

      def tax_scope
        candidates = @candidates || self.class.candidates_for([ @transaction ])
        candidates.select do |candidate|
          candidate.id != @transaction.id && candidate.source_booking_id == @booking.id &&
            candidate.booking_folio.hotel_id == @folio.hotel_id && candidate.charge? && !candidate.reversed? &&
            (candidate.category == "tax" || candidate.metadata.key?("tax_line"))
        end
      end

      def attached_by_parent?(candidate)
        parent_transaction_id(candidate).to_s == @transaction.id.to_s
      end

      def attached_by_tax_rule?(candidate)
        return false if parent_transaction_id(candidate).present?
        return false unless same_stay_date?(candidate)

        source_code_ids.include?(source_transaction_code_id(candidate)) || expected_tax_code_ids.include?(candidate.transaction_code_id)
      end

      def parent_transaction_id(candidate)
        candidate.parent_transaction_id.presence || candidate.metadata.to_h["parent_folio_transaction_id"].presence ||
          candidate.metadata.to_h[:parent_folio_transaction_id].presence || candidate.metadata.to_h["parent_transaction_id"].presence
      end

      def same_stay_date?(candidate)
        candidate_date = metadata_stay_date(candidate) || candidate.posting_date&.iso8601
        candidate_date.present? && candidate_date == parent_stay_date
      end

      def parent_stay_date
        @parent_stay_date ||= metadata_stay_date(@transaction) || @transaction.posting_date&.iso8601
      end

      def metadata_stay_date(transaction)
        transaction.metadata.to_h["stay_date"].presence || transaction.metadata.to_h[:stay_date].presence
      end

      def source_transaction_code_id(candidate)
        metadata = candidate.metadata.to_h
        tax_line = metadata["tax_line"].to_h.with_indifferent_access
        (tax_line[:source_transaction_code_id].presence || metadata["source_transaction_code_id"].presence || metadata[:source_transaction_code_id].presence).to_i
      end

      def source_code_ids
        [ @transaction.transaction_code_id ].compact
      end

      def expected_tax_code_ids
        @expected_tax_code_ids ||= begin
          return [] if @transaction.transaction_code.blank?

          Folios::Routing::EffectiveTaxRules.call(booking: @transaction.booking_folio.booking, transaction_code: @transaction.transaction_code).filter_map do |tax_rule|
            next unless tax_rule.enabled_for_posting?

            tax_rule.posting_transaction_code&.id
          end
        end
      end
    end
  end
end
