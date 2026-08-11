# frozen_string_literal: true

module HotelPortal
  module Reports
    # Reconciles OTA settlement expectations with receipts. Amounts are never
    # combined across currencies, and summaries use the actual OTA source rather
    # than the channel manager that delivered the booking.
    class ChannelSettlementReport
      Result = Struct.new(
        :start_date, :end_date, :rows, :summary_rows, :detail_rows,
        :attention_rows, :currency_totals, :totals_by_currency, :totals,
        :grand_total, keyword_init: true
      ) do
        def summary_rows
          self[:summary_rows] || rows
        end
      end

      def initialize(hotel:, start_date: nil, end_date: nil, query: nil,
                     source: nil, currency: nil, status: nil, statuses: nil)
        @hotel = hotel
        @start_date = start_date&.to_date
        @end_date = end_date&.to_date
        @query = query.to_s.strip
        @source = source.to_s.presence
        @currency = currency.to_s.upcase.presence
        requested_statuses = Array(statuses.presence || status).map(&:to_s)
        @statuses = requested_statuses & ChannelSettlement::STATUSES
      end

      def call
        details = settlements.map { |settlement| detail_row(settlement) }
        rows = grouped_rows(details)
        currency_totals = rows
          .group_by { |row| row[:currency] }
          .map { |currency, currency_rows| sum_row(currency, currency_rows) }
          .sort_by { |row| row[:currency] }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          summary_rows: rows,
          detail_rows: details,
          attention_rows: attention_rows(details),
          currency_totals: currency_totals,
          totals_by_currency: currency_totals.index_by { |row| row[:currency] },
          totals: currency_totals,
          grand_total: nil
        )
      end

      private

      def settlements
        scope = @hotel.channel_settlements
          .where(collection_by: "ota")
          .includes(
            :booking_source,
            channel_settlement_allocations: [
              :booking,
              :channel_settlement_receipt_allocations
            ]
          )
        scope = scope.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day) if @start_date && @end_date
        scope = scope.where(booking_source_id: @source) if @source
        scope = scope.where(currency: @currency) if @currency
        scope = scope.where(status: @statuses) if @statuses.any?
        scope = search(scope) if @query.present?
        @settlements ||= scope.order(created_at: :desc, id: :desc).to_a
      end

      def search(scope)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
        scope.left_joins(channel_settlement_allocations: :booking)
          .where(
            <<~SQL.squish,
              LOWER(channel_settlements.channel_manager_reference) LIKE :query OR
              LOWER(bookings.confirmation_token) LIKE :query OR
              LOWER(bookings.guest_name) LIKE :query
            SQL
            query: pattern
          )
          .distinct
      end

      def attention_rows(details)
        details.filter_map do |row|
          settlement = row[:settlement]
          message = settlement.metadata.to_h["reconciliation_error"]
          next unless settlement.needs_attention? || message.present?

          row.slice(:ota, :reference, :currency, :booking_references).merge(
            message: message.presence || "Settlement needs operator review",
            failed_at: settlement.metadata.to_h["reconciliation_failed_at"]
          )
        end
      end

      def grouped_rows(details)
        details
          .group_by { |row| [ row[:booking_source_id], row[:ota], row[:currency] ] }
          .map do |(booking_source_id, ota, currency), grouped|
            amounts_for(
              booking_source_id: booking_source_id,
              ota: ota,
              currency: currency,
              expected: grouped.sum { |row| row[:expected_net_amount] },
              received: grouped.sum { |row| row[:received_amount] }
            )
          end
          .sort_by { |row| [ row[:ota].downcase, row[:currency] ] }
      end

      def detail_row(settlement)
        allocations = settlement.channel_settlement_allocations
        expected = if allocations.empty?
          settlement.expected_net_amount.to_d
        else
          allocations.sum { |allocation| allocation.expected_net_amount.to_d }
        end
        received = allocations.sum do |allocation|
          allocation.channel_settlement_receipt_allocations.sum do |receipt_allocation|
            receipt_allocation.amount.to_d
          end
        end
        bookings = allocations.filter_map(&:booking).uniq(&:id)

        amounts_for(
          settlement: settlement,
          booking_source_id: settlement.booking_source_id,
          ota: settlement.booking_source.label,
          currency: settlement.currency,
          reference: settlement.channel_manager_reference,
          status: settlement.status,
          bookings: bookings,
          booking_references: bookings.map(&:confirmation_token),
          expected: expected,
          received: received
        )
      end

      def sum_row(currency, rows)
        amounts_for(
          currency: currency,
          expected: rows.sum { |row| row[:expected_net_amount] },
          received: rows.sum { |row| row[:received_amount] }
        )
      end

      def amounts_for(expected:, received:, **attributes)
        expected = expected.to_d.round(2)
        received = received.to_d.round(2)
        outstanding = (expected - received).round(2)
        variance = (received - expected).round(2)

        attributes.merge(
          expected_net_amount: expected,
          received_amount: received,
          outstanding_amount: outstanding,
          variance_amount: variance,
          expected: expected,
          received: received,
          outstanding: outstanding,
          variance: variance
        )
      end
    end
  end
end
