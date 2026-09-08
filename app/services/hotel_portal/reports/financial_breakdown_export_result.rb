# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownExportResult
      KEYS = %i[booking_number confirmation_code guest_name status check_in check_out gross taxes margin net currency].freeze
      MONEY_KEYS = %i[gross taxes margin net].freeze
      attr_reader :start_date, :end_date, :rows, :currency_totals, :totals_by_currency

      def initialize(start_date:, end_date:, rows:)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @rows = rows.map do |row|
          KEYS.index_with do |key|
            value = row.fetch(key)
            if MONEY_KEYS.include?(key)
              value.to_d
            elsif key == :currency
              value.to_s.presence || "MYR"
            else
              value
            end
          end.freeze
        end.freeze
        @currency_totals = build_currency_totals.freeze
        @totals_by_currency = @currency_totals.index_by { |totals| totals.fetch(:currency) }.freeze
        freeze
      end

      private

      def build_currency_totals
        @rows.group_by { |row| row.fetch(:currency).to_s }
             .sort_by(&:first)
             .map do |currency, rows|
          MONEY_KEYS.index_with { |key| rows.sum { |row| row.fetch(key) } }
                    .merge(currency: currency, booking_count: rows.size)
                    .freeze
        end
      end
    end
  end
end
