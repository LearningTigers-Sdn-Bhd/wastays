# frozen_string_literal: true

require "caxlsx"

module HotelPortal
  module Reports
    class ExtraChargeExcelExportService
      COLORS = ExcelExportStyles::COLORS
      FONT_SIZES = ExcelExportStyles::FONT_SIZES
      COLUMN_WIDTHS = [ 15, 22, 20, 24, 42, 20, 12, 16 ].freeze
      DETAIL_TEXT_WIDTHS = {
        booking_reference: 22,
        folio_number: 20,
        guest_name: 24,
        description: 42,
        category: 20,
        currency: 12
      }.freeze
      DETAIL_LINE_HEIGHT = 15
      MAX_ROW_HEIGHT = 409

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        package = Axlsx::Package.new
        @workbook = package.workbook
        build_styles
        build_workbook

        package.to_stream.read
      end

      private

      def build_styles
        styles = @workbook.styles
        @styles = {
          title: styles.add_style(
            bg_color: COLORS[:primary], fg_color: COLORS[:white], b: true, sz: FONT_SIZES[:title],
            alignment: { vertical: :center }
          ),
          metadata: styles.add_style(
            fg_color: COLORS[:muted], sz: FONT_SIZES[:body],
            alignment: { vertical: :top, wrap_text: true }
          ),
          section: styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:section],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }
          ),
          header: styles.add_style(
            bg_color: COLORS[:ink], fg_color: COLORS[:white], b: true, sz: FONT_SIZES[:body],
            alignment: { vertical: :center, wrap_text: true }
          ),
          body: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top, wrap_text: true }
          ),
          body_alt: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top, wrap_text: true }
          ),
          wrapped: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top, wrap_text: true }
          ),
          wrapped_alt: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top, wrap_text: true }
          ),
          date: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "yyyy-mm-dd",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top }
          ),
          date_alt: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "yyyy-mm-dd",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top }
          ),
          integer: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "#,##0",
            alignment: { horizontal: :right }
          ),
          kpi: styles.add_style(
            fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value],
            format_code: "#,##0.00;[Red]-#,##0.00", alignment: { horizontal: :right }
          ),
          summary_label: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:muted], b: true, sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :top, :bottom, :left, :right ] },
            alignment: { vertical: :center }
          ),
          summary_integer: styles.add_style(
            fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value], format_code: "#,##0",
            border: { style: :thin, color: COLORS[:border], edges: [ :top, :bottom, :left, :right ] },
            alignment: { horizontal: :center, vertical: :center }
          ),
          summary_money: styles.add_style(
            fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value],
            format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:border], edges: [ :top, :bottom, :left, :right ] },
            alignment: { horizontal: :right, vertical: :center }
          ),
          summary_currency: styles.add_style(
            fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :top, :bottom, :left, :right ] },
            alignment: { horizontal: :center, vertical: :center }
          ),
          money: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { horizontal: :right, vertical: :top }
          ),
          money_alt: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { horizontal: :right, vertical: :top }
          ),
          total_label: styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:primary], edges: [ :top ] }
          ),
          total_money: styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:primary], edges: [ :top ] },
            alignment: { horizontal: :right }
          ),
          empty: styles.add_style(
            fg_color: COLORS[:muted], sz: FONT_SIZES[:body], i: true,
            alignment: { vertical: :center }
          )
        }
      end

      def build_workbook
        @workbook.add_worksheet(name: sheet_name) do |sheet|
          sheet.sheet_view.zoom_scale = 100
          sheet.page_setup.orientation = :landscape
          sheet.page_setup.fit_to_width = 1
          sheet.page_setup.fit_to_height = 0

          add_report_header(sheet)
          add_summary(sheet)
          add_charge_table(sheet)
          sheet.column_widths(*COLUMN_WIDTHS)
        end
      end

      def add_report_header(sheet)
        sheet.add_row([ "Extra Charge Report - #{tab_label}" ], style: [ @styles[:title] ], height: 34)
        sheet.merge_cells("A1:H1")
        sheet.add_row([ @hotel.name.to_s ], style: [ @styles[:metadata] ], height: 20)
        sheet.merge_cells("A2:H2")
        sheet.add_row([ "Reporting period: #{period_label}" ], style: [ @styles[:metadata] ], height: 20)
        sheet.merge_cells("A3:H3")
        sheet.add_row([ "Generated: #{Time.current.strftime('%d %b %Y, %H:%M %Z')}" ], style: [ @styles[:metadata] ], height: 20)
        sheet.merge_cells("A4:H4")
      end

      def add_summary(sheet)
        sheet.add_row([ "Summary" ], style: [ @styles[:section] ], height: 24)
        sheet.merge_cells("A5:H5")
        sheet.add_row(
          [ "Transactions", nil, nil, nil, "Total Amount" ],
          style: Array.new(8, @styles[:summary_label]), height: 26
        )
        sheet.merge_cells("A6:D6")
        sheet.merge_cells("E6:H6")
        sheet.add_row(
          [ transaction_count, nil, nil, nil, total_amount, nil, nil, currency ],
          style: [ *@styles.values_at(:summary_integer, :summary_integer, :summary_integer, :summary_integer),
            *@styles.values_at(:summary_money, :summary_money, :summary_money), @styles[:summary_currency] ],
          height: 32
        )
        sheet.merge_cells("A7:D7")
        sheet.merge_cells("E7:G7")
        sheet.add_row([ "Charge Details" ], style: [ @styles[:section] ], height: 24)
        sheet.merge_cells("A8:H8")
      end

      def add_charge_table(sheet)
        header_row = sheet.rows.size + 1
        sheet.add_row(ExtraChargeCsvExportService::HEADERS, style: Array.new(8, @styles[:header]), height: 28)

        if @report.rows.any?
          @report.rows.each_with_index do |row, index|
            sheet.add_row(detail_values(row), style: detail_styles(index), height: detail_row_height(row))
          end
        else
          sheet.add_row([ "No extra charge transactions found for this period." ], style: [ @styles[:empty] ], height: 22)
          sheet.merge_cells("A#{sheet.rows.size}:H#{sheet.rows.size}")
        end

        sheet.add_row(total_values, style: total_styles, height: 26)
        last_detail_row = header_row + [ @report.rows.size, 1 ].max
        sheet.auto_filter = "A#{header_row}:H#{last_detail_row}"
        freeze_at(sheet, header_row)
      end

      def detail_values(row)
        [
          row[:posting_date], row[:booking_reference], row[:folio_number], row[:guest_name],
          row[:description], category_label(row[:category]), currency, decimal(row[:amount])
        ]
      end

      def detail_styles(index)
        alternate = index.odd?
        [
          alternate ? @styles[:date_alt] : @styles[:date],
          alternate ? @styles[:body_alt] : @styles[:body],
          alternate ? @styles[:body_alt] : @styles[:body],
          alternate ? @styles[:body_alt] : @styles[:body],
          alternate ? @styles[:wrapped_alt] : @styles[:wrapped],
          alternate ? @styles[:body_alt] : @styles[:body],
          alternate ? @styles[:body_alt] : @styles[:body],
          alternate ? @styles[:money_alt] : @styles[:money]
        ]
      end

      def detail_row_height(row)
        values_and_widths = [
          [ row[:booking_reference], DETAIL_TEXT_WIDTHS[:booking_reference] ],
          [ row[:folio_number], DETAIL_TEXT_WIDTHS[:folio_number] ],
          [ row[:guest_name], DETAIL_TEXT_WIDTHS[:guest_name] ],
          [ row[:description], DETAIL_TEXT_WIDTHS[:description] ],
          [ category_label(row[:category]), DETAIL_TEXT_WIDTHS[:category] ],
          [ currency, DETAIL_TEXT_WIDTHS[:currency] ]
        ]
        line_count = values_and_widths.map { |value, width| wrapped_line_count(value, width) }.max

        [ [ line_count * DETAIL_LINE_HEIGHT, 26 ].max, MAX_ROW_HEIGHT ].min
      end

      def wrapped_line_count(value, column_width)
        value.to_s.lines(chomp: true).sum do |line|
          [ (line.scan(/\X/).length.to_f / column_width).ceil, 1 ].max
        end
      end

      def total_values
        [ "Total", nil, nil, nil, nil, "#{transaction_count} #{'transaction'.pluralize(transaction_count)}", currency, total_amount ]
      end

      def total_styles
        [ *@styles.values_at(:total_label, :total_label, :total_label, :total_label, :total_label, :total_label, :total_label), @styles[:total_money] ]
      end

      def freeze_at(sheet, header_row)
        sheet.sheet_view.pane do |pane|
          pane.state = :frozen
          pane.y_split = header_row
          pane.top_left_cell = "A#{header_row + 1}"
          pane.active_pane = :bottom_left
        end
      end

      def sheet_name
        "#{tab_label}"
      end

      def tab_label
        @report.active_tab == "fb" ? "F&B Charges" : "Non-F&B Charges"
      end

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end

      def transaction_count
        @report.totals[:transaction_count]
      end

      def total_amount
        decimal(@report.totals[:total_amount])
      end

      def decimal(value)
        value.to_d.to_f
      end

      def category_label(value)
        return "F&B" if value.to_s == "fb"

        value.to_s.humanize
      end
    end
  end
end
