# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownPdfExportService
      HEADERS = [ "Booking", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Commission", "Net", "Currency" ].freeze
      COLUMN_WIDTHS = [ 188, 140, 54, 55, 55, 55, 48, 64, 55, 48 ].freeze

      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Financial Breakdown", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        if @report.currency_totals.empty?
          add_table(builder, currency, nil)
        else
          @report.currency_totals.each_with_index do |totals, index|
            builder.start_new_page unless index.zero?
            currency_code = totals.fetch(:currency)
            builder.add_summary(summary_metrics(totals, currency_code))
            add_table(builder, currency_code, totals)
          end
        end
        builder.render
      end

      private

      def add_table(builder, currency_code, totals)
        builder.add_table(
          section_title: "#{currency_code} Booking Details",
          headers: HEADERS,
          rows: rows_for(currency_code).map { |row| pdf_row(row) },
          numeric_columns: [ 5, 6, 7, 8 ],
          total_row: totals && [ "TOTAL", nil, nil, nil, nil, *totals.values_at(:gross, :taxes, :margin, :net).map { |value| money(value) }, currency_code ],
          empty_message: "No bookings found for the selected criteria.",
          column_widths: COLUMN_WIDTHS,
          density: :dense
        )
      end

      def pdf_row(row)
        [
          { content: "#{row[:booking_number]}\nCode: #{row[:confirmation_code]}" },
          row[:guest_name], row[:status].to_s.titleize, date(row[:check_in]), date(row[:check_out]),
          money(row[:gross]), money(row[:taxes]), money(row[:margin]), money(row[:net]), row[:currency]
        ]
      end

      def summary_metrics(totals, currency_code)
        [
          [ "Gross Price", amount(totals, :gross, currency_code) ],
          [ "Taxes", amount(totals, :taxes, currency_code) ],
          [ "Commission", amount(totals, :margin, currency_code) ],
          [ "Net Payout", amount(totals, :net, currency_code) ]
        ]
      end

      def rows_for(currency_code) = @report.rows.select { |row| row.fetch(:currency) == currency_code }
      def amount(totals, key, currency_code) = "#{currency_code} #{money(totals.fetch(key))}"
      def money(value) = Exports::PdfTheme.money(value)
      def date(value) = value&.strftime("%d %b %Y") || "-"
      def period_label = "#{date(@report.start_date)} - #{date(@report.end_date)}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
