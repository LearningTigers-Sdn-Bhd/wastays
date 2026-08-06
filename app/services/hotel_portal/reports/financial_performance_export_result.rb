# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialPerformanceExportResult
      attr_reader :start_date, :end_date, :totals, :rows

      def initialize(start_date:, end_date:, totals:, rows:)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @totals = {
          gross: totals.fetch(:gross).to_d,
          margin: totals.fetch(:margin).to_d,
          net: totals.fetch(:net).to_d,
          booking_count: totals.fetch(:booking_count).to_i
        }.freeze
        @rows = rows.map do |row|
          {
            date: row.fetch(:date).to_date,
            booking_count: row.fetch(:booking_count).to_i,
            gross: row.fetch(:gross).to_d,
            margin: row.fetch(:margin).to_d,
            net: row.fetch(:net).to_d
          }.freeze
        end.freeze
        freeze
      end
    end
  end
end
