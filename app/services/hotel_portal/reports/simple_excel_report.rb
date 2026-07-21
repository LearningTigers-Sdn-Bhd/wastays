# frozen_string_literal: true

require "caxlsx"

module HotelPortal
  module Reports
    module SimpleExcelReport
      COLORS = {
        ink: "18332F",
        primary: "205B4E",
        primary_light: "E7F1ED",
        muted: "667772",
        border: "D9E4DF",
        stripe: "F5F8F7",
        white: "FFFFFF"
      }.freeze

      def build_workbook
        package = Axlsx::Package.new
        package.use_shared_strings = true
        @workbook = package.workbook
        build_excel_styles
        yield
        package.to_stream.read
      end

      def add_report_sheet(title:, column_count:, widths:, period_label:)
        sheet = @workbook.add_worksheet(name: title.to_s.truncate(31), show_gridlines: false)
        sheet.column_widths(*widths)
        sheet.page_setup.orientation = column_count > 6 ? :landscape : :portrait
        sheet.page_setup.fit_to_width = 1
        sheet.page_setup.fit_to_height = 0

        last_column = excel_column_letter(column_count)
        sheet.add_row([ "#{@hotel.name} — #{title}" ], style: [ @excel_styles[:title] ], height: 26)
        sheet.merge_cells("A1:#{last_column}1")
        sheet.add_row([ "Reporting period: #{period_label}" ], style: [ @excel_styles[:metadata] ])
        sheet.merge_cells("A2:#{last_column}2")
        sheet.add_row([])
        sheet
      end

      def add_data_table(sheet, headers:, rows:, money_columns: [], total_row: nil)
        header_row = sheet.rows.size + 1
        sheet.add_row(headers, style: Array.new(headers.size, @excel_styles[:header]), height: 24)

        rows.each_with_index do |values, index|
          styles = Array.new(headers.size, index.odd? ? @excel_styles[:body_alt] : @excel_styles[:body])
          money_columns.each { |i| styles[i] = @excel_styles[:money] }
          sheet.add_row(values, style: styles, height: 20)
        end

        if total_row
          styles = Array.new(headers.size, @excel_styles[:total_label])
          money_columns.each { |i| styles[i] = @excel_styles[:total_number] }
          sheet.add_row(total_row, style: styles, height: 20)
        end

        last_row = header_row + [ rows.size, 1 ].max
        sheet.auto_filter = "A#{header_row}:#{excel_column_letter(headers.size)}#{last_row}"
      end

      def decimal(value)
        value.to_d.to_f
      end

      private

      def build_excel_styles
        styles = @workbook.styles
        @excel_styles = {
          title: styles.add_style(bg_color: COLORS[:primary], fg_color: COLORS[:white], b: true, sz: 16, alignment: { vertical: :center }),
          metadata: styles.add_style(fg_color: COLORS[:muted], sz: 9),
          header: styles.add_style(bg_color: COLORS[:ink], fg_color: COLORS[:white], b: true, sz: 10, alignment: { vertical: :center, wrap_text: true }),
          body: styles.add_style(fg_color: COLORS[:ink], sz: 10, border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }),
          body_alt: styles.add_style(bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: 10, border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }),
          money: styles.add_style(fg_color: COLORS[:ink], sz: 10, format_code: "#,##0.00;[Red]-#,##0.00", border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }, alignment: { horizontal: :right }),
          total_label: styles.add_style(bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: 10, border: { style: :thin, color: COLORS[:primary], edges: [ :top ] }),
          total_number: styles.add_style(bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: 10, format_code: "#,##0.00;[Red]-#,##0.00", border: { style: :thin, color: COLORS[:primary], edges: [ :top ] }, alignment: { horizontal: :right })
        }
      end

      def excel_column_letter(column_count)
        number = column_count
        letters = +""
        while number.positive?
          number, remainder = (number - 1).divmod(26)
          letters.prepend((65 + remainder).chr)
        end
        letters
      end
    end
  end
end
