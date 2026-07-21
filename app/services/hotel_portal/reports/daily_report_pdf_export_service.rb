# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class DailyReportPdfExportService
      COLORS = {
        ink: "18332F",
        primary: "205B4E",
        primary_light: "E7F1ED",
        muted: "667772",
        border: "D9E4DF",
        stripe: "F5F8F7",
        white: "FFFFFF",
        negative: "A33636"
      }.freeze

      def initialize(hotel:, tab:, revenue_report:, cashier_report:, charge_register: [])
        @hotel = hotel
        @tab = tab
        @revenue_report = revenue_report
        @cashier_report = cashier_report
        @charge_register = charge_register
      end

      def generate
        pdf = Prawn::Document.new(
          page_size: "A4",
          page_layout: @tab == "overview" ? :portrait : :landscape,
          margin: [ 40, 32, 42, 32 ]
        )

        draw_header(pdf)
        case @tab
        when "revenue" then draw_revenue_report(pdf)
        when "cashier" then draw_cashier_report(pdf)
        else draw_overview_report(pdf)
        end
        draw_footer(pdf)

        pdf.render
      end

      private

      def draw_header(pdf)
        top = pdf.cursor
        pdf.fill_color COLORS[:primary]
        pdf.fill_rectangle([ 0, top ], pdf.bounds.width, 58)
        pdf.fill_color COLORS[:white]
        pdf.text_box "DAILY REPORT", at: [ 16, top - 14 ], width: 250, height: 20, size: 16, style: :bold
        pdf.text_box tab_title, at: [ 16, top - 36 ], width: 250, height: 16, size: 9

        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        pdf.image logo_path, at: [ pdf.bounds.right - 145, top - 10 ], width: 125 if File.exist?(logo_path)

        pdf.move_down 70
        pdf.fill_color COLORS[:ink]
        pdf.text @hotel.name.to_s, size: 12, style: :bold
        pdf.move_down 2
        pdf.fill_color COLORS[:muted]
        pdf.text "Reporting period: #{period_label}", size: 9
        pdf.text "Generated: #{Time.current.strftime('%d %b %Y, %H:%M %Z')}", size: 8
        pdf.fill_color COLORS[:ink]
        pdf.move_down 14
      end

      def draw_footer(pdf)
        pdf.number_pages "Page <page> of <total>",
          at: [ 0, -8 ], width: pdf.bounds.width, align: :center, size: 7, color: COLORS[:muted]
      end

      def draw_overview_report(pdf)
        draw_kpi_section(pdf, "Revenue (Accrual)", revenue_kpis)
        pdf.move_down 18
        draw_kpi_section(pdf, "Cashier Sales (Cash Flow)", cashier_kpis)
        pdf.move_down 18
        draw_note(pdf, "Revenue records when charges are earned. Cashier Sales records when payments or refunds move.")
      end

      def draw_revenue_report(pdf)
        draw_kpi_section(pdf, "Revenue Summary", revenue_kpis)
        pdf.move_down 16
        draw_revenue_table(pdf, "Daily Breakdown", @revenue_report.rows, :date)
        pdf.move_down 16
        draw_revenue_table(pdf, "Revenue by Source", @revenue_report.source_rows, :source)
        pdf.start_new_page(layout: :landscape)
        draw_section_heading(pdf, "Revenue Register", "Revenue charges and adjustments posted during the reporting period")
        draw_charge_register(pdf)
      end

      def draw_cashier_report(pdf)
        draw_kpi_section(pdf, "Cashier Sales Summary", cashier_kpis)
        pdf.move_down 16
        draw_cashier_transaction_table(pdf, "Advance", @cashier_report.advance_scope)
        pdf.start_new_page(layout: :landscape)
        draw_cashier_transaction_table(pdf, "Settlement", @cashier_report.settlement_scope)
        pdf.start_new_page(layout: :landscape)
        draw_cashier_summaries(pdf)
      end

      def draw_kpi_section(pdf, title, cards)
        draw_section_heading(pdf, title)
        data = [ cards.map(&:first), cards.map(&:last) ]
        table = pdf.make_table(data, width: pdf.bounds.width, cell_style: { padding: [ 8, 9 ], border_color: COLORS[:border] })
        table.row(0).style(
          background_color: COLORS[:primary_light], text_color: COLORS[:muted],
          size: 7, font_style: :bold, borders: [ :bottom ]
        )
        table.row(1).style(text_color: COLORS[:ink], size: 12, font_style: :bold, borders: [])
        table.draw
      end

      def draw_revenue_table(pdf, title, rows, label_key)
        draw_section_heading(pdf, title)
        if rows.empty?
          draw_empty_state(pdf, "No revenue data for this selected period.")
          return
        end

        label_header = label_key == :date ? "Date" : "Source"
        data = rows.map do |row|
          [
            label_key == :date ? row[:date].strftime("%d %b %Y") : row[:source],
            row[:booking_count].to_s,
            money(row[:accommodation]), money(row[:other_charges]), money(row[:tax]),
            money(row[:total_charges]), money(row[:adjustments]), money(row[:net_revenue])
          ]
        end
        totals = @revenue_report.totals
        data << [
          "Total", totals[:booking_count].to_s, money(totals[:accommodation]), money(totals[:other_charges]),
          money(totals[:tax]), money(totals[:total_charges]), money(totals[:adjustments]), money(totals[:net_revenue])
        ]

        draw_data_table(
          pdf,
          [ label_header, "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Adjustments", "Net Revenue" ],
          data,
          numeric_columns: (1..7).to_a,
          total_row: data.size
        )
      end

      def draw_charge_register(pdf)
        negative_cells = []
        rows = @charge_register.each_with_index.map do |row, index|
          negative_cells << [ index, 5 ] if row.signed_amount.negative?
          negative_cells << [ index, 6 ] if row.tax_amount.negative?
          negative_cells << [ index, 7 ] if row.total_amount.negative?

          [
            date_time_label(row),
            [ row.service_name, (row.transaction_code unless row.transaction_code == "—") ].compact.join("\n"),
            "#{row.booking_reference}\nFolio #{row.folio_number}",
            [ row.guest_name, row.room_details ].compact.join("\n"),
            row.relationship_status,
            "#{row.currency} #{money(row.signed_amount)}",
            "#{row.currency} #{money(row.tax_amount)}",
            "#{row.currency} #{money(row.total_amount)}"
          ]
        end

        if rows.empty?
          draw_empty_state(pdf, "No records for this selected period.")
          return
        end

        amount_total = @charge_register.sum(&:signed_amount)
        tax_total = @charge_register.sum(&:tax_amount)
        total_amount = amount_total + tax_total
        rows << [ "Total", nil, nil, nil, nil, "MYR #{money(amount_total)}", "MYR #{money(tax_total)}", "MYR #{money(total_amount)}" ]
        draw_data_table(
          pdf,
          [ "Date & Time", "Service / Code", "Booking / Folio", "Guest / Room Details", "Status", "Base Amount", "Tax", "Total Amount" ],
          rows,
          numeric_columns: [ 5, 6, 7 ], negative_cells: negative_cells, total_row: rows.size,
          column_widths: [ 65, 125, 125, 115, 60, 84, 78, 90 ]
        )
      end

      def draw_cashier_transaction_table(pdf, title, transactions)
        draw_section_heading(pdf, title, "Payment movements classified as #{title.downcase}")
        rows = transactions.map { |transaction| cashier_transaction_row(transaction) }
        if rows.empty?
          draw_empty_state(pdf, "No records for this selected period.")
          return
        end

        total = transactions.sum { |transaction| DailyReportTransactionRow.new(transaction).signed_amount }
        rows << [ "Total", nil, nil, nil, nil, nil, nil, nil, "MYR #{money(total)}" ]
        draw_data_table(
          pdf,
          DailyReportTransactionRow::CASHIER_VISUAL_HEADERS,
          rows,
          numeric_columns: [ 8 ], total_row: rows.size,
          column_widths: [ 68, 96, 92, 74, 55, 82, 72, 170, 69 ]
        )
      end

      def cashier_transaction_row(transaction)
        row = DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id]
        )
        [
          date_time_label(row),
          row.booking_reference,
          "#{row.guest_name}\nRoom #{row.room_number}",
          row.folio_number,
          row.invoice_number.to_s,
          row.settlement_mode,
          row.received_by,
          row.description,
          "#{row.currency} #{money(row.signed_amount)}"
        ]
      end

      def draw_cashier_summaries(pdf)
        draw_section_heading(pdf, "Cashier Summary", "Amounts grouped by payment mode")
        rows = @cashier_report.mode_summary_rows.map do |row|
          [ row[:mode], row[:currency], row[:section], money(row[:amount_in]), money(row[:amount_out]), money(row[:balance]) ]
        end
        rows += @cashier_report.mode_totals.map do |row|
          [ "#{row[:mode]} Total", nil, nil, money(row[:amount_in]), money(row[:amount_out]), money(row[:balance]) ]
        end

        if rows.present?
          draw_data_table(
            pdf,
            [ "Payment Mode", "Currency", "Section", "Amount In", "Amount Out", "Balance" ],
            rows,
            numeric_columns: [ 3, 4, 5 ]
          )
        else
          draw_empty_state(pdf, "No cashier activity for this selected period.")
        end

        pdf.move_down 18
        draw_section_heading(pdf, "Currency Summary", "Cash movement totals by currency")
        currency_rows = @cashier_report.currency_summary_rows.map do |row|
          [ row[:currency], row[:section], money(row[:amount_in]), money(row[:amount_out]), money(row[:balance]) ]
        end
        grand = @cashier_report.grand_total
        currency_rows << [ "Grand Total", nil, money(grand[:amount_in]), money(grand[:amount_out]), money(grand[:balance]) ]

        if @cashier_report.currency_summary_rows.present?
          draw_data_table(
            pdf,
            [ "Currency", "Section", "Amount In", "Amount Out", "Balance" ],
            currency_rows,
            numeric_columns: [ 2, 3, 4 ], total_row: currency_rows.size
          )
        else
          draw_empty_state(pdf, "No cashier activity for this selected period.")
        end
      end

      def draw_data_table(pdf, headers, rows, numeric_columns: [], negative_cells: [], total_row: nil, column_widths: nil)
        options = {
          header: true,
          width: column_widths ? column_widths.sum : pdf.bounds.width,
          cell_style: {
            size: 7.5,
            padding: [ 5, 6 ],
            border_color: COLORS[:border],
            borders: [ :bottom ],
            text_color: COLORS[:ink],
            overflow: :shrink_to_fit,
            min_font_size: 6
          }
        }
        options[:column_widths] = column_widths if column_widths

        table = pdf.make_table([ headers ] + rows, options)
        table.row(0).style(
          background_color: COLORS[:ink], text_color: COLORS[:white],
          font_style: :bold, size: 7, borders: []
        )
        rows.each_index do |index|
          table.row(index + 1).background_color = COLORS[:stripe] if index.odd?
        end
        numeric_columns.each { |column| table.column(column).style(align: :right) }
        negative_cells.each do |row, column|
          table.row(row + 1).column(column).style(text_color: COLORS[:negative])
        end
        if total_row
          table.row(total_row).style(
            background_color: COLORS[:primary_light], font_style: :bold,
            borders: [ :top ], border_color: COLORS[:primary]
          )
        end
        table.draw
      end

      def draw_section_heading(pdf, title, subtitle = nil)
        pdf.fill_color COLORS[:ink]
        pdf.text title, size: 11, style: :bold
        if subtitle
          pdf.move_down 2
          pdf.fill_color COLORS[:muted]
          pdf.text subtitle, size: 7.5
        end
        pdf.fill_color COLORS[:ink]
        pdf.move_down 6
      end

      def draw_empty_state(pdf, message)
        pdf.fill_color COLORS[:muted]
        pdf.text message, size: 9, style: :italic
        pdf.fill_color COLORS[:ink]
      end

      def draw_note(pdf, message)
        pdf.fill_color COLORS[:primary_light]
        pdf.fill_rectangle([ 0, pdf.cursor ], pdf.bounds.width, 42)
        pdf.fill_color COLORS[:ink]
        pdf.text_box message, at: [ 12, pdf.cursor - 12 ], width: pdf.bounds.width - 24, height: 24, size: 9
        pdf.move_down 50
      end

      def revenue_kpis
        totals = @revenue_report.totals
        [
          [ "Bookings Engaged", totals[:booking_count].to_s ],
          [ "Total Charges", "MYR #{money(totals[:total_charges])}" ],
          [ "Adjustments", "MYR #{money(totals[:adjustments])}" ],
          [ "Net Revenue", "MYR #{money(totals[:net_revenue])}" ]
        ]
      end

      def cashier_kpis
        totals = @cashier_report.totals
        [
          [ "Cash Movements", totals[:movement_count].to_s ],
          [ "Total Collected", "MYR #{money(totals[:total_collected])}" ],
          [ "Total Refunded", "MYR #{money(totals[:total_refunded])}" ],
          [ "Net Cash", "MYR #{money(totals[:net_cash])}" ]
        ]
      end

      def date_time_label(row)
        [ row.posting_date.strftime("%d %b %Y"), row.transaction_time.strftime("%-I:%M %p") ].join("\n")
      end

      def tab_title
        { "revenue" => "Revenue", "cashier" => "Cashier Sales" }.fetch(@tab, "Overview")
      end

      def period_label
        return @revenue_report.start_date.strftime("%d %b %Y") if @revenue_report.start_date == @revenue_report.end_date

        "#{@revenue_report.start_date.strftime('%d %b %Y')} - #{@revenue_report.end_date.strftime('%d %b %Y')}"
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
