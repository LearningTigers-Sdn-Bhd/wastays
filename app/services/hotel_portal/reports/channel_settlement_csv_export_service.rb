# frozen_string_literal: true

module HotelPortal
  module Reports
    class ChannelSettlementCsvExportService
      HEADERS = [
        "OTA", "Booking", "Settlement Reference", "Status", "Currency",
        "Expected Net", "Received", "Outstanding", "Variance"
      ].freeze

      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << HEADERS
          @report.detail_rows.group_by { |row| row[:currency] }.sort.each do |currency, rows|
            rows.each { |row| csv << detail_values(row) }

            total = @report.totals_by_currency.fetch(currency)
            csv << [
              "TOTAL", "", "", "", @csv.text(currency),
              @csv.money(total[:expected_net_amount]),
              @csv.money(total[:received_amount]),
              @csv.money(total[:outstanding_amount]),
              @csv.money(total[:variance_amount])
            ]
          end
        end
      end

      private

      def status_label(status)
        status.humanize.gsub(/\bota\b/i, "OTA")
      end

      def detail_values(row)
        [
          @csv.text(row[:ota]),
          @csv.text(row[:booking_references].to_sentence),
          @csv.text(row[:reference]),
          @csv.text(status_label(row[:status])),
          @csv.text(row[:currency]),
          @csv.money(row[:expected_net_amount]),
          @csv.money(row[:received_amount]),
          @csv.money(row[:outstanding_amount]),
          @csv.money(row[:variance_amount])
        ]
      end
    end
  end
end
