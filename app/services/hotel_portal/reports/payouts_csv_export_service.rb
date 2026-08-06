# frozen_string_literal: true

module HotelPortal
  module Reports
    class PayoutsCsvExportService
      UPCOMING_HEADERS = [ "Booking Reference", "Checked Out At", "Status", "Currency", "Net Amount" ].freeze
      BATCH_HEADERS = [ "Period Start", "Period End", "Status", "Reference", "Currency", "Net Amount" ].freeze
      PAID_HEADERS = [ "Period Start", "Period End", "Settled At", "Status", "Reference", "Currency", "Net Amount" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          @report.paid? ? add_paid_rows(csv) : add_upcoming_rows(csv)
        end
      end

      private

      def add_upcoming_rows(csv)
        csv << UPCOMING_HEADERS
        @report.upcoming_rows.each do |row|
          csv << [
            @csv.text(row[:booking_reference]), @csv.text(datetime(row[:checked_out_at])),
            @csv.text(row[:status].to_s.titleize), @csv.text(currency), @csv.money(row[:net_amount])
          ]
        end
        csv << []
        csv << [ "Processing Batches" ]
        csv << BATCH_HEADERS
        @report.processing_rows.each do |row|
          csv << [
            @csv.date(row[:period_start]), @csv.date(row[:period_end]), @csv.text(row[:status].to_s.titleize),
            @csv.text(row[:reference].presence || "-"), @csv.text(currency), @csv.money(row[:net_amount])
          ]
        end
      end

      def add_paid_rows(csv)
        csv << PAID_HEADERS
        @report.paid_rows.each do |row|
          csv << [
            @csv.date(row[:period_start]), @csv.date(row[:period_end]), @csv.text(datetime(row[:settled_at])),
            @csv.text(row[:status].to_s.titleize), @csv.text(row[:reference].presence || "-"),
            @csv.text(currency), @csv.money(row[:net_amount])
          ]
        end
      end

      def datetime(value)
        value&.strftime("%Y-%m-%d %H:%M") || "-"
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end
    end
  end
end
