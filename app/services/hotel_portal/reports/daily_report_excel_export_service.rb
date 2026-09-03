# frozen_string_literal: true

require "caxlsx"

module HotelPortal
  module Reports
    class DailyReportExcelExportService
      CASHIER_HEADERS = [
        "Date & Time", "Reservation", "Guest", "Room", "Folio", "Invoice",
        "Payment Mode", "Type", "Received By", "Remarks", "Currency", "Amount"
      ].freeze

      COLORS = ExcelExportStyles::COLORS
      FONT_SIZES = ExcelExportStyles::FONT_SIZES

      def initialize(hotel:, tab:, revenue_report:, cashier_report:, charge_register: [])
        @hotel = hotel
        @tab = tab
        @revenue_report = revenue_report
        @cashier_report = cashier_report
        @charge_register = charge_register
      end

      def generate
        package = Axlsx::Package.new
        @workbook = package.workbook
        build_styles

        case @tab
        when "revenue" then build_revenue_workbook
        when "cashier" then build_cashier_workbook
        else build_overview_workbook
        end

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
          metadata: styles.add_style(fg_color: COLORS[:muted], sz: FONT_SIZES[:body]),
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
            alignment: { vertical: :top }
          ),
          body_alt: styles.add_style(
            bg_color: COLORS[:stripe], fg_color: COLORS[:ink], sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { vertical: :top }
          ),
          date: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "yyyy-mm-dd",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }
          ),
          datetime: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "yyyy-mm-dd hh:mm",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] }
          ),
          integer: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "#,##0",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { horizontal: :right }
          ),
          money: styles.add_style(
            fg_color: COLORS[:ink], sz: FONT_SIZES[:body], format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:border], edges: [ :bottom ] },
            alignment: { horizontal: :right }
          ),
          total_label: styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            border: { style: :thin, color: COLORS[:primary], edges: [ :top ] }
          ),
          total_number: styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            format_code: "#,##0.00;[Red]-#,##0.00",
            border: { style: :thin, color: COLORS[:primary], edges: [ :top ] },
            alignment: { horizontal: :right }
          ),
          kpi_label: styles.add_style(fg_color: COLORS[:muted], sz: FONT_SIZES[:body]),
          kpi_value: styles.add_style(fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value], format_code: "#,##0.00;[Red]-#,##0.00")
        }
      end

      def build_overview_workbook
        sheet = add_sheet("Overview", 4, widths: [ 28, 18, 14, 18 ])
        add_report_header(sheet, "Overview", 4)
        add_metric_section(sheet, "Revenue (Accrual)", [
          [ "Bookings Engaged", @revenue_report.totals[:booking_count], nil ],
          [ "Total Charges", decimal(@revenue_report.totals[:total_charges]), "MYR" ],
          [ "Adjustments", decimal(@revenue_report.totals[:adjustments]), "MYR" ],
          [ "Net Revenue", decimal(@revenue_report.totals[:net_revenue]), "MYR" ]
        ])
        sheet.add_row([])
        add_metric_section(sheet, "Cashier Activity (Cash Flow)", [
          [ "Cash Movements", @cashier_report.totals[:movement_count], nil ],
          [ "Total Collected", decimal(@cashier_report.totals[:total_collected]), "MYR" ],
          [ "Total Refunded", decimal(@cashier_report.totals[:total_refunded]), "MYR" ],
          [ "Net Cash", decimal(@cashier_report.totals[:net_cash]), "MYR" ]
        ])
      end

      def build_revenue_workbook
        daily = add_sheet("Daily Breakdown", 8, widths: [ 14, 11, 18, 18, 15, 18, 17, 18 ])
        add_report_header(daily, "Revenue - Daily Breakdown", 8)
        add_metric_section(daily, "Revenue Summary", revenue_metrics)
        daily.add_row([])
        add_table(
          daily,
          headers: [ "Date", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Adjustments", "Net Revenue" ],
          rows: @revenue_report.rows.map { |row| revenue_row(row, :date) },
          date_columns: [ 0 ], integer_columns: [ 1 ], money_columns: (2..7).to_a,
          total_row: [ "Total", @revenue_report.totals[:booking_count], decimal(@revenue_report.totals[:accommodation]),
            decimal(@revenue_report.totals[:other_charges]), decimal(@revenue_report.totals[:tax]),
            decimal(@revenue_report.totals[:total_charges]), decimal(@revenue_report.totals[:adjustments]),
            decimal(@revenue_report.totals[:net_revenue]) ]
        )

        source = add_sheet("Revenue by Source", 8, widths: [ 24, 11, 18, 18, 15, 18, 17, 18 ])
        add_report_header(source, "Revenue by Source", 8)
        add_table(
          source,
          headers: [ "Source", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Adjustments", "Net Revenue" ],
          rows: @revenue_report.source_rows.map { |row| revenue_row(row, :source) },
          integer_columns: [ 1 ], money_columns: (2..7).to_a,
          total_row: [ "Total", @revenue_report.totals[:booking_count], decimal(@revenue_report.totals[:accommodation]),
            decimal(@revenue_report.totals[:other_charges]), decimal(@revenue_report.totals[:tax]),
            decimal(@revenue_report.totals[:total_charges]), decimal(@revenue_report.totals[:adjustments]),
            decimal(@revenue_report.totals[:net_revenue]) ]
        )

        register = add_sheet("Revenue Register", 14, widths: charge_register_widths)
        add_report_header(register, "Revenue Register", 14)
        rows = @charge_register.map { |row| charge_register_row(row) }
        add_table(
          register,
          headers: DailyRevenueTransactionsCsvExportService::HEADERS,
          rows: rows,
          date_columns: [ 0 ], datetime_columns: [ 1 ], money_columns: [ 10, 11, 12 ],
          total_row: total_for_register(rows, 14, amount_indexes: [ 10, 11, 12 ])
        )
      end

      def build_cashier_workbook
        activity = add_sheet("Cashier Activity", CASHIER_HEADERS.size, widths: cashier_widths)
        add_report_header(activity, "Cashier Activity", CASHIER_HEADERS.size)
        add_metric_section(activity, "Cashier Activity Summary", cashier_metrics)
        activity.add_row([])
        activity_rows = cashier_rows(@cashier_report.cash_transactions)
        add_table(
          activity, headers: CASHIER_HEADERS, rows: activity_rows,
          datetime_columns: [ 0 ], money_columns: [ 11 ], total_row: total_for_cashier(activity_rows)
        )

        summary = add_sheet("Cashier Summary", 6, widths: [ 28, 13, 16, 18, 18, 18 ])
        add_report_header(summary, "Cashier Summary", 6)
        summary_rows = @cashier_report.mode_summary_rows.map do |row|
          [ row[:mode], row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        summary_rows += @cashier_report.mode_totals.map do |row|
          [ "#{row[:mode]} Total", nil, nil, decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        add_table(
          summary,
          headers: [ "Payment Mode", "Currency", "Section", "Amount In", "Amount Out", "Balance" ],
          rows: summary_rows, money_columns: [ 3, 4, 5 ]
        )

        currency = add_sheet("Currency Summary", 5, widths: [ 16, 18, 20, 20, 20 ])
        add_report_header(currency, "Currency Summary", 5)
        currency_rows = @cashier_report.currency_summary_rows.map do |row|
          [ row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        grand = @cashier_report.grand_total
        add_table(
          currency,
          headers: [ "Currency", "Section", "Amount In", "Amount Out", "Balance" ],
          rows: currency_rows, money_columns: [ 2, 3, 4 ],
          total_row: [ "Grand Total", nil, decimal(grand[:amount_in]), decimal(grand[:amount_out]), decimal(grand[:balance]) ]
        )

        return if @cashier_report.non_cash_transactions.empty?

        non_cash = add_sheet("Not Counted As Cash", CASHIER_HEADERS.size, widths: cashier_widths)
        add_report_header(non_cash, "Not Counted As Cash", CASHIER_HEADERS.size)
        non_cash_rows = cashier_rows(@cashier_report.non_cash_transactions)
        add_table(
          non_cash, headers: CASHIER_HEADERS, rows: non_cash_rows,
          datetime_columns: [ 0 ], money_columns: [ 11 ], total_row: total_for_cashier(non_cash_rows)
        )
      end

      def add_sheet(name, column_count, widths:)
        @workbook.add_worksheet(name: name, show_gridlines: false) do |sheet|
          sheet.column_widths(*widths)
          sheet.sheet_view.zoom_scale = 100
          sheet.page_setup.orientation = column_count > 6 ? :landscape : :portrait
          sheet.page_setup.fit_to_width = 1
          sheet.page_setup.fit_to_height = 0
          return sheet
        end
      end

      def add_report_header(sheet, section_name, column_count)
        last_column = column_letter(column_count)
        sheet.add_row([ "Daily Report - #{section_name}" ], style: [ @styles[:title] ], height: 28)
        sheet.merge_cells("A1:#{last_column}1")
        sheet.add_row([ @hotel.name.to_s ], style: [ @styles[:metadata] ])
        sheet.merge_cells("A2:#{last_column}2")
        sheet.add_row([ "Reporting period: #{period_label}" ], style: [ @styles[:metadata] ])
        sheet.merge_cells("A3:#{last_column}3")
        sheet.add_row([ "Generated: #{Time.current.strftime('%d %b %Y, %H:%M %Z')}" ], style: [ @styles[:metadata] ])
        sheet.merge_cells("A4:#{last_column}4")
      end

      def add_metric_section(sheet, title, metrics)
        column_count = [ sheet.column_info.size, 3 ].max
        last_column = column_letter(column_count)
        sheet.add_row([ title ], style: [ @styles[:section] ])
        sheet.merge_cells("A#{sheet.rows.size}:#{last_column}#{sheet.rows.size}")
        sheet.add_row([ "Metric", "Value", "Currency" ], style: Array.new(3, @styles[:header]))
        metrics.each do |label, value, currency|
          value_style = value.is_a?(Integer) ? @styles[:integer] : @styles[:kpi_value]
          sheet.add_row([ label, value, currency ], style: [ @styles[:kpi_label], value_style, @styles[:body] ], height: 22)
        end
      end

      def add_table(sheet, headers:, rows:, money_columns: [], date_columns: [], datetime_columns: [], integer_columns: [], total_row: nil)
        header_row = sheet.rows.size + 1
        sheet.add_row(headers, style: Array.new(headers.size, @styles[:header]), height: 28)

        rows.each_with_index do |values, index|
          styles = row_styles(
            headers.size, index,
            money_columns: money_columns,
            date_columns: date_columns,
            datetime_columns: datetime_columns,
            integer_columns: integer_columns
          )
          sheet.add_row(values, style: styles, height: 22)
        end

        if total_row
          styles = Array.new(headers.size, @styles[:total_label])
          money_columns.each { |index| styles[index] = @styles[:total_number] }
          integer_columns.each { |index| styles[index] = @styles[:total_label] }
          sheet.add_row(total_row, style: styles, height: 22)
        end

        last_data_row = header_row + [ rows.size, 1 ].max
        sheet.auto_filter = "A#{header_row}:#{column_letter(headers.size)}#{last_data_row}"
        freeze_at(sheet, header_row)
      end

      def freeze_at(sheet, header_row)
        sheet.sheet_view.pane do |pane|
          pane.state = :frozen
          pane.y_split = header_row
          pane.top_left_cell = "A#{header_row + 1}"
          pane.active_pane = :bottom_left
        end
      end

      def row_styles(column_count, row_index, money_columns:, date_columns:, datetime_columns:, integer_columns:)
        styles = Array.new(column_count, row_index.odd? ? @styles[:body_alt] : @styles[:body])
        money_columns.each { |index| styles[index] = @styles[:money] }
        date_columns.each { |index| styles[index] = @styles[:date] }
        datetime_columns.each { |index| styles[index] = @styles[:datetime] }
        integer_columns.each { |index| styles[index] = @styles[:integer] }
        styles
      end

      def revenue_metrics
        [
          [ "Bookings Engaged", @revenue_report.totals[:booking_count], nil ],
          [ "Total Charges", decimal(@revenue_report.totals[:total_charges]), "MYR" ],
          [ "Adjustments", decimal(@revenue_report.totals[:adjustments]), "MYR" ],
          [ "Net Revenue", decimal(@revenue_report.totals[:net_revenue]), "MYR" ]
        ]
      end

      def cashier_metrics
        [
          [ "Cash Movements", @cashier_report.totals[:movement_count], nil ],
          [ "Total Collected", decimal(@cashier_report.totals[:total_collected]), "MYR" ],
          [ "Total Refunded", decimal(@cashier_report.totals[:total_refunded]), "MYR" ],
          [ "Net Cash", decimal(@cashier_report.totals[:net_cash]), "MYR" ]
        ]
      end

      def revenue_row(row, label_key)
        [
          row[label_key], row[:booking_count], decimal(row[:accommodation]), decimal(row[:other_charges]),
          decimal(row[:tax]), decimal(row[:total_charges]), decimal(row[:adjustments]), decimal(row[:net_revenue])
        ]
      end

      def charge_register_row(row)
        [
          row.posting_date, row.transaction_time.to_datetime, row.service_name, row.transaction_code,
          row.booking_reference, row.folio_number, row.guest_name, row.room_number,
          row.room_type_name, row.relationship_status, decimal(row.signed_amount), decimal(row.tax_amount),
          decimal(row.total_amount), row.currency
        ]
      end

      def cashier_rows(transactions)
        transactions.map do |transaction|
          row = cashier_row(transaction)
          [
            transaction_datetime(row), row.booking_reference, row.guest_name, row.room_number,
            row.folio_number, row.invoice_number, row.settlement_mode, row.section, row.received_by,
            row.description, row.currency, decimal(row.signed_amount)
          ]
        end
      end

      def cashier_row(transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id],
          section: @cashier_report.section_by_transaction_id[transaction.id]
        )
      end

      def transaction_datetime(row)
        time = row.posted_at
        return row.posting_date unless time

        DateTime.new(row.posting_date.year, row.posting_date.month, row.posting_date.day, time.hour, time.min, time.sec)
      end

      def total_for_cashier(rows)
        total = rows.sum { |row| row[11].to_d }
        [ "Total", *Array.new(9), rows.first&.[](10) || "MYR", decimal(total) ]
      end

      def total_for_register(rows, column_count, amount_indexes:)
        values = Array.new(column_count)
        values[0] = "Total"
        amount_indexes.each do |index|
          values[index] = decimal(rows.sum { |row| row[index].to_d })
        end
        values
      end

      def charge_register_widths
        [ 14, 20, 24, 16, 24, 20, 22, 12, 24, 16, 16, 16, 16, 12 ]
      end

      def cashier_widths
        [ 20, 25, 22, 12, 20, 16, 24, 14, 20, 42, 12, 16 ]
      end

      def period_label
        return @revenue_report.start_date.strftime("%d %b %Y") if @revenue_report.start_date == @revenue_report.end_date

        "#{@revenue_report.start_date.strftime('%d %b %Y')} - #{@revenue_report.end_date.strftime('%d %b %Y')}"
      end

      def column_letter(column_count)
        number = column_count
        letters = +""
        while number.positive?
          number, remainder = (number - 1).divmod(26)
          letters.prepend((65 + remainder).chr)
        end
        letters
      end

      def decimal(value)
        value.to_d.to_f
      end
    end
  end
end
