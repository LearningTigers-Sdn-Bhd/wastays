# frozen_string_literal: true

require "cgi"
require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module AccountsReceivable
    class GenerateStatement
      DARK_GREEN = "0a2e29"
      LIGHT_GRAY = "f9fafb"
      BORDER_GRAY = "e5e7eb"
      TEXT_PRIMARY = "111827"
      TEXT_MUTED = "6b7280"
      SUCCESS = "059669"
      BOTTOM_MARGIN = 72
      FOOTER_Y = -26

      def initialize(report:, printed_by: nil)
        @report = report
        @printed_by = printed_by.presence || "-"
      end

      def generate
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: "Account Statement - #{@report.corporate_account.name}",
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        draw_header(pdf)
        pdf.move_down 14
        draw_hotel_information(pdf)
        pdf.move_down 12
        draw_statement_information(pdf)
        pdf.move_down 16
        draw_transactions(pdf)
        pdf.move_down 16
        draw_summary(pdf)
        pdf.move_down 14
        draw_aging(pdf)
        pdf.move_down 14
        draw_notes(pdf)
        draw_footer(pdf)

        pdf.render
      end

      private

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, height: 32
        else
          pdf.fill_color DARK_GREEN
          pdf.text "WAStays", size: 22, style: :bold
        end

        pdf.move_up 32
        pdf.fill_color DARK_GREEN
        pdf.text "ACCOUNT STATEMENT", size: 18, style: :bold, align: :right
        pdf.move_down 12
        pdf.stroke_color DARK_GREEN
        pdf.line_width 0.5
        pdf.stroke_horizontal_rule
        pdf.line_width 1
        pdf.fill_color TEXT_PRIMARY
      end

      def draw_hotel_information(pdf)
        rows = [
          [ "Hotel Name", @report.hotel.name ],
          [ "Address", hotel_address ],
          [ "Contact", hotel_contact ]
        ].select { |_label, value| value.present? }

        section_title(pdf, "HOTEL INFORMATION")
        detail_table(pdf, rows)
      end

      def draw_statement_information(pdf)
        left_rows = [
          [ "Corporate Account", @report.corporate_account.name ],
          [ "Contact Email", @report.contact_email.presence || "-" ],
          [ "Currency", @report.currency ]
        ]
        right_rows = [
          [ "Statement Period", "#{format_date(@report.start_date)} - #{format_date(@report.end_date)}" ],
          [ "Payment Terms", payment_terms ],
          [ "Closing Balance", money(@report.closing_balance) ]
        ]
        row_count = [ left_rows.size, right_rows.size ].max
        rows = [
          [
            { content: "ACCOUNT DETAILS", colspan: 2, font_style: :bold, background_color: LIGHT_GRAY },
            { content: "STATEMENT DETAILS", colspan: 2, font_style: :bold, background_color: LIGHT_GRAY }
          ]
        ]
        rows += row_count.times.map do |index|
          left = left_rows[index] || [ "", "" ]
          right = right_rows[index] || [ "", "" ]
          [ label_cell(left.first), value_cell(left.last), label_cell(right.first), value_cell(right.last) ]
        end

        label_width = 84
        value_width = (pdf.bounds.width - (label_width * 2)) / 2.0
        pdf.table(rows, width: pdf.bounds.width, column_widths: [ label_width, value_width, label_width, value_width ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 7, 5, 7 ]
          cells.size = 8
          row(0).padding = [ 6, 7, 6, 7 ]
        end
      end

      def draw_transactions(pdf)
        rows = [
          [
            header_cell("Date"),
            header_cell("Type"),
            header_cell("Reference"),
            header_cell("Description"),
            header_cell("Due"),
            header_cell("Debit", align: :right),
            header_cell("Credit", align: :right),
            header_cell("Balance", align: :right)
          ]
        ]

        if @report.ledger_rows.empty?
          rows << [ { content: "No AR activity in this statement period.", colspan: 8, align: :center, text_color: TEXT_MUTED } ]
        else
          @report.ledger_rows.each do |row|
            rows << [
              body_cell(format_date(row.effective_date), color: TEXT_MUTED),
              body_cell(row.record_type),
              body_cell(row.reference),
              body_cell(row.description),
              body_cell(row.due_on ? format_date(row.due_on) : "-", color: TEXT_MUTED),
              money_cell(row.debit),
              money_cell(row.credit, credit: row.credit.to_d.positive?),
              money_cell(row.balance, balance: true)
            ]
          end
        end

        pdf.table(rows, width: pdf.bounds.width, header: true, column_widths: transaction_widths(pdf)) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 4, 5, 4 ]
          cells.size = 6.8
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
        end
      end

      def transaction_widths(pdf)
        width = pdf.bounds.width
        [ 48, 42, 58, width - 48 - 42 - 58 - 48 - 58 - 58 - 64, 48, 58, 58, 64 ]
      end

      def draw_summary(pdf)
        section_title(pdf, "STATEMENT SUMMARY (#{@report.currency})", width: pdf.bounds.width * 0.52, position: :right)
        rows = [
          [ "Opening Balance", @report.opening_balance ],
          [ "Invoices", @report.period_invoices ],
          [ "Payments", -@report.period_payments ],
          [ "Closing Balance", @report.closing_balance ],
          [ "Unapplied Credit", -@report.unapplied_credit ]
        ]
        width = pdf.bounds.width * 0.52
        pdf.table(
          rows.map.with_index do |(label, amount), index|
            [
              { content: label, font_style: index == 3 ? :bold : :normal },
              { content: money(amount), align: :right, font_style: index == 3 ? :bold : :normal, text_color: amount.negative? ? SUCCESS : TEXT_PRIMARY }
            ]
          end,
          width: width,
          position: :right,
          column_widths: [ width * 0.62, width * 0.38 ]
        ) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
        end
      end

      def draw_aging(pdf)
        section_title(pdf, "INVOICE AGING AS OF #{format_date(@report.end_date).upcase}")
        aging = @report.aging
        rows = [
          [ "Current", "1-30", "31-60", "61-90", "90+", "Total" ].map { |label| header_cell(label, align: :right) },
          [
            aging.current,
            aging.days_1_30,
            aging.days_31_60,
            aging.days_61_90,
            aging.days_over_90,
            aging.total
          ].map { |amount| money_cell(amount) }
        ]
        pdf.table(rows, width: pdf.bounds.width) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 7, 5, 7 ]
          cells.size = 7.5
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
        end
      end

      def draw_notes(pdf)
        section_title(pdf, "NOTES")
        pdf.table(@report.notes.map { |note| [ { content: note, text_color: TEXT_MUTED } ] }, width: pdf.bounds.width) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 7.5
        end
      end

      def draw_footer(pdf)
        pdf.repeat(:all) do
          pdf.stroke_color BORDER_GRAY
          pdf.line_width 0.5
          pdf.stroke_horizontal_line(pdf.bounds.left, pdf.bounds.right, at: FOOTER_Y + 14)
          pdf.bounding_box([ pdf.bounds.left, FOOTER_Y ], width: pdf.bounds.width - 88, height: 12) do
            pdf.fill_color TEXT_MUTED
            pdf.text "Printed at #{Time.current.strftime('%d %b %Y %H:%M')} by #{@printed_by}", size: 7
          end
        end

        pdf.number_pages "Page <page> of <total>",
          at: [ pdf.bounds.right - 75, FOOTER_Y ],
          size: 7,
          color: TEXT_MUTED
      end

      def detail_table(pdf, rows)
        pdf.table(rows.map { |label, value| [ label_cell(label), value_cell(value) ] }, width: pdf.bounds.width, column_widths: [ 120, pdf.bounds.width - 120 ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 4, 7, 4, 7 ]
          cells.size = 8
        end
      end

      def section_title(pdf, title, width: pdf.bounds.width, position: nil)
        pdf.table([ [ { content: title, font_style: :bold, text_color: TEXT_PRIMARY } ] ], width: width, position: position) do
          cells.background_color = LIGHT_GRAY
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
        end
      end

      def label_cell(value)
        { content: escape(value), text_color: TEXT_MUTED, font_style: :bold }
      end

      def value_cell(value)
        { content: escape(value), text_color: TEXT_PRIMARY }
      end

      def header_cell(value, align: :left)
        { content: value, text_color: TEXT_MUTED, align: align }
      end

      def body_cell(value, color: TEXT_PRIMARY)
        { content: escape(value.to_s.presence || "-"), text_color: color }
      end

      def money_cell(amount, credit: false, balance: false)
        value = amount.to_d
        {
          content: value.zero? ? "-" : format_amount(value),
          align: :right,
          text_color: credit || (balance && value.negative?) ? SUCCESS : TEXT_PRIMARY
        }
      end

      def money(amount)
        "#{@report.currency} #{format_amount(amount)}"
      end

      def format_amount(amount)
        format("%.2f", amount.to_d)
      end

      def format_date(date)
        date.strftime("%d %b %Y")
      end

      def payment_terms
        days = @report.hotel_corporate_account.payment_terms_days
        return "-" if days.nil?
        return "Due on receipt" if days.zero?

        "Net #{days} days"
      end

      def hotel_address
        [ @report.hotel.address, @report.hotel.city, @report.hotel.country ].compact_blank.join(", ")
      end

      def hotel_contact
        [ @report.hotel.contact_phone, @report.hotel.contact_email ].compact_blank.join(" · ")
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
