# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class ExtraChargeCsvExportService
      BOM = "\uFEFF".freeze
      DANGEROUS_TEXT_PREFIX = /\A[=+\-@\t\r]/
      HEADERS = [
        "Posting Date", "Booking Reference", "Folio Reference", "Guest Name",
        "Description", "Category", "Currency", "Amount"
      ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        BOM + CSV.generate do |csv|
          csv << HEADERS

          @report.rows.each do |row|
            csv << [
              row[:posting_date].iso8601,
              safe_text_cell(row[:booking_reference]),
              safe_text_cell(row[:folio_number]),
              safe_text_cell(row[:guest_name]),
              safe_text_cell(row[:description]),
              safe_text_cell(category_label(row[:category])),
              safe_text_cell(currency),
              money(row[:amount])
            ]
          end

          count = @report.totals[:transaction_count]
          csv << [ "TOTAL", nil, nil, nil, nil, "#{count} #{'transaction'.pluralize(count)}", safe_text_cell(currency), money(@report.totals[:total_amount]) ]
        end
      end

      private

      def money(value)
        format("%.2f", value.to_d)
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end

      # Spreadsheet applications can interpret text beginning with these
      # characters as a formula. Prefixing an apostrophe preserves the visible
      # text while forcing every user-controlled textual field to remain data.
      def safe_text_cell(value)
        return value if value.nil?

        text = value.to_s
        text.match?(DANGEROUS_TEXT_PREFIX) ? "'#{text}" : text
      end

      def category_label(value)
        return "F&B" if value.to_s == "fb"

        value.to_s.humanize
      end
    end
  end
end
