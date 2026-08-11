# frozen_string_literal: true

module HotelPortal
  module Reports
    # Reconciles OTA settlement expectations with the receipt amounts allocated
    # to those expectations.  Amounts are never combined across currencies.
    class ChannelSettlementReport
      Result = Struct.new(
        :start_date, :end_date, :rows, :summary_rows, :attention_rows, :currency_totals, :totals_by_currency, :totals, :grand_total,
        keyword_init: true
      ) do
        # `summary_rows` is the descriptive name used by settlement consumers;
        # `rows` remains the conventional report API.
        def summary_rows
          self[:summary_rows] || rows
        end
      end

      def initialize(hotel:, start_date: nil, end_date: nil)
        @hotel = hotel
        @start_date = start_date&.to_date
        @end_date = end_date&.to_date
      end

      def call
        rows = grouped_rows
        currency_totals = rows
          .group_by { |row| row[:currency] }
          .map { |currency, currency_rows| sum_row(currency, currency_rows) }
          .sort_by { |row| row[:currency] }
        totals_by_currency = currency_totals.index_by { |row| row[:currency] }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          summary_rows: rows,
          attention_rows: attention_rows,
          currency_totals: currency_totals,
          totals_by_currency: totals_by_currency,
          # A numeric grand total would be misleading when currencies differ.
          totals: currency_totals,
          grand_total: nil
        )
      end

      private

      def settlements
        scope = @hotel.channel_settlements
          .where(collection_by: "ota")
          .includes(:booking_source, channel_settlement_allocations: [ :channel_settlement_receipt_allocations ])

        scope = scope.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day) if @start_date && @end_date
        @settlements ||= scope.to_a
      end

      def attention_rows
        settlements.filter_map do |settlement|
          message = settlement.metadata.to_h["reconciliation_error"]
          next unless settlement.needs_attention? || message.present?

          {
            provider: settlement.provider,
            booking_source: settlement.booking_source.label,
            reference: settlement.channel_manager_reference,
            currency: settlement.currency,
            message: message.presence || "Settlement needs operator review",
            failed_at: settlement.metadata.to_h["reconciliation_failed_at"]
          }
        end
      end

      def grouped_rows
        settlements
          .group_by { |settlement| [ settlement.provider, settlement.currency ] }
          .map { |(provider, currency), grouped| row_for(provider, currency, grouped) }
          .sort_by { |row| [ row[:provider], row[:currency] ] }
      end

      def row_for(provider, currency, grouped)
        expected = grouped.sum { |settlement| expected_for(settlement) }
        received = grouped.sum { |settlement| received_for(settlement) }
        amounts_for(provider: provider, currency: currency, expected: expected, received: received)
      end

      def expected_for(settlement)
        allocations = settlement.channel_settlement_allocations
        return settlement.expected_net_amount.to_d if allocations.empty?

        allocations.sum { |allocation| allocation.expected_net_amount.to_d }
      end

      def received_for(settlement)
        settlement.channel_settlement_allocations.sum do |allocation|
          allocation.channel_settlement_receipt_allocations.sum { |receipt_allocation| receipt_allocation.amount.to_d }
        end
      end

      def sum_row(currency, rows)
        expected = rows.sum { |row| row[:expected_net_amount].to_d }
        received = rows.sum { |row| row[:received_amount].to_d }
        amounts_for(currency: currency, expected: expected, received: received)
      end

      def amounts_for(provider: nil, currency:, expected:, received:)
        expected = expected.round(2)
        received = received.round(2)
        outstanding = (expected - received).round(2)
        variance = (received - expected).round(2)

        {
          provider: provider,
          currency: currency,
          # Explicit amount names are useful at call sites, while the short
          # aliases keep the report easy to consume in tabular presenters.
          expected_net_amount: expected,
          received_amount: received,
          outstanding_amount: outstanding,
          variance_amount: variance,
          expected: expected,
          received: received,
          outstanding: outstanding,
          variance: variance
        }.compact
      end
    end
  end
end
