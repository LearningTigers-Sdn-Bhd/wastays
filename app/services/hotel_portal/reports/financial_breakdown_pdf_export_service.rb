# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownPdfExportService
      def initialize(hotel:, report:, prepared_by:, visible_columns: BookingPerformanceColumns::DEFAULT_KEYS)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
        @visible_columns = visible_columns
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Booking Performance", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape, frame_variant: :compact)
        builder.add_header
        if @report.totals_by_currency.empty?
          add_table(builder, currency, nil)
        else
          @report.totals_by_currency.each_with_index do |totals, index|
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
        groups = @report.groups.select { |group| group.rows.any? { |row| row.currency == currency_code } }
        if groups.empty?
          draw_table(builder, "#{currency_code} booking details", table_for([]), nil)
          return
        end

        groups.each do |group|
          rows = group.rows.select { |row| row.currency == currency_code }
          group_totals = group.currency_totals.find { |item| item.fetch(:currency) == currency_code }
          draw_table(builder, group.label, table_for(rows), group_totals)
        end
      end

      def draw_table(builder, title, table, totals)
        rows = table.pdf_rows.map { |row| format_money_cells(row, table.pdf_money_indexes) }
        total_row = totals && format_money_cells(table.total_row(totals, pdf: true), table.pdf_money_indexes)
        builder.add_table(
          section_title: title,
          headers: table.pdf_headers,
          rows:,
          numeric_columns: table.pdf_money_indexes,
          total_row:,
          empty_message: "No bookings found for the selected criteria.",
          column_widths: table.pdf_widths(builder.content_width),
          density: :dense
        )
      end

      def format_money_cells(row, indexes)
        row.map.with_index { |value, index| value && indexes.include?(index) ? money(value) : value }
      end

      def table_for(rows) = BookingPerformanceExportTable.new(rows:, visible_columns: @visible_columns)

      def summary_metrics(totals, currency_code)
        [
          [ "Gross Price", amount(totals, :gross, currency_code) ],
          [ "Taxes", amount(totals, :taxes, currency_code) ],
          [ "Commission", amount(totals, :commission, currency_code) ],
          [ "Net Payout", amount(totals, :net, currency_code) ]
        ]
      end

      def amount(totals, key, currency_code) = "#{currency_code} #{money(totals.fetch(key))}"
      def money(value) = Exports::PdfTheme.money(value)
      def date(value) = value&.strftime("%d %b %Y") || "-"
      def period_label = "#{date(@report.start_date)} - #{date(@report.end_date)}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
