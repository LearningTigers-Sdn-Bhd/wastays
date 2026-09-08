# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownExcelExportService
      def initialize(hotel:, report:, visible_columns: BookingPerformanceColumns::DEFAULT_KEYS)
        @hotel = hotel
        @report = report
        @visible_columns = visible_columns
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Booking Performance", period_label: period_label).generate do |builder|
          if @report.totals_by_currency.empty?
            add_sheet(builder, currency, nil)
          else
            @report.totals_by_currency.each { |totals| add_sheet(builder, totals.fetch(:currency), totals) }
          end
        end
      end

      private

      def add_sheet(builder, currency_code, totals)
        rows = rows_for(currency_code)
        table = table_for(rows)
        sheet = builder.add_sheet(
          name: "#{currency_code} Booking Performance",
          widths: table.excel_widths,
          orientation: :landscape
        )
        builder.add_header(sheet: sheet, subtitle: currency_code)
        builder.add_summary(sheet: sheet, metrics: summary_metrics(totals, currency_code)) if totals
        groups_for(currency_code).each do |group|
          group_rows = group.rows.select { |row| row.currency == currency_code }
          next if group_rows.empty?

          group_table = table_for(group_rows)
          group_totals = group.currency_totals.find { |item| item.fetch(:currency) == currency_code }
          add_table(builder, sheet, group.label, group_table, group_totals)
        end
        add_table(builder, sheet, "Booking details", table, nil) if rows.empty?
      end

      def summary_metrics(totals, currency_code)
        [
          [ "Gross Price", totals.fetch(:gross), currency_code ],
          [ "Taxes", totals.fetch(:taxes), currency_code ],
          [ "Commission", totals.fetch(:commission), currency_code ],
          [ "Net Payout", totals.fetch(:net), currency_code ]
        ]
      end

      def rows_for(currency_code)
        @report.ordered_rows.select { |row| row.currency == currency_code }
      end

      def groups_for(currency_code)
        @report.groups.select { |group| group.rows.any? { |row| row.currency == currency_code } }
      end

      def add_table(builder, sheet, title, table, totals)
        builder.add_table(
          sheet:,
          section_title: title,
          headers: table.headers,
          rows: table.rows,
          column_types: table.column_types,
          total_row: totals && table.total_row(totals),
          empty_message: "No bookings found for the selected criteria."
        )
      end

      def table_for(rows) = BookingPerformanceExportTable.new(rows:, visible_columns: @visible_columns)

      def period_label = "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
