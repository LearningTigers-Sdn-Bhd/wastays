# frozen_string_literal: true

module HotelPortal
  module Reports
    class ChannelSettlementCsvExportService
      HEADERS = [ "Provider", "Currency", "Expected Net", "Received", "Outstanding", "Variance" ].freeze

      def initialize(report:)
        @report = report
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << HEADERS
          @report.rows.group_by { |row| row[:currency] }.sort.each do |currency, rows|
            rows.each do |row|
              csv << [
                @csv.text(row[:provider].to_s.titleize),
                @csv.text(currency),
                @csv.money(row[:expected_net_amount]),
                @csv.money(row[:received_amount]),
                @csv.money(row[:outstanding_amount]),
                @csv.money(row[:variance_amount])
              ]
            end

            total = @report.totals_by_currency.fetch(currency)
            csv << [
              "TOTAL",
              @csv.text(currency),
              @csv.money(total[:expected_net_amount]),
              @csv.money(total[:received_amount]),
              @csv.money(total[:outstanding_amount]),
              @csv.money(total[:variance_amount])
            ]
          end
        end
      end
    end
  end
end
