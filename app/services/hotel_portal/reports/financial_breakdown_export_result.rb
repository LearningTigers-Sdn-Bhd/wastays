# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownExportResult
      KEYS = %i[booking_reference guest_name status check_in check_out gross taxes margin net currency].freeze
      attr_reader :start_date, :end_date, :rows

      def initialize(start_date:, end_date:, rows:)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @rows = rows.map do |row|
          KEYS.index_with do |key|
            value = row.fetch(key)
            %i[gross taxes margin net].include?(key) ? value.to_d : value
          end.freeze
        end.freeze
        @totals = %i[gross taxes margin net].index_with { |key| @rows.sum { |row| row[key] } }.freeze
        freeze
      end

      def totals
        @totals
      end
    end
  end
end
