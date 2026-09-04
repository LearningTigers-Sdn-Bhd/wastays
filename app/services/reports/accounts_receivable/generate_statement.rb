# frozen_string_literal: true

require "cgi"

module Reports
  module AccountsReceivable
    class GenerateStatement
      Exports = HotelPortal::Reports::Exports

      def initialize(report:, printed_by: nil, detail: false)
        @report = report
        @printed_by = printed_by.presence || "-"
        @detail = detail
      end

      def generate
        generated_at = Time.current
        builder = Exports::PdfReportBuilder.new(
          hotel: @report.hotel,
          title: "Account Statement",
          period_label: nil,
          prepared_by: @printed_by,
          metadata: [],
          generated_at: generated_at,
          page_layout: :landscape,
          confidential: false
        )
        builder.add_header
        builder.add_party_blocks(party_blocks(generated_at))
        builder.add_summary(balance_metrics)
        add_aging(builder)
        @detail ? add_invoice_details(builder) : add_summary_ledger(builder)
        add_statement_summary(builder)
        builder.render
      end

      private

      def period_label
        "#{format_date(@report.start_date)} - #{format_date(@report.end_date)}"
      end

      def party_blocks(generated_at)
        address = CorporateAccounts::BillingAddressPresenter.new(@report.hotel_corporate_account)
        [
          {
            heading: "Corporate account",
            entries: [
              [ "Name", @report.corporate_account.name ],
              [ "Billing address", address.display.presence || "Not provided" ],
              [ "Contact email", @report.contact_email.presence || "-" ],
              [ "Contact phone", @report.hotel_corporate_account.contact_phone.presence || "-" ]
            ]
          },
          {
            heading: "Statement details",
            entries: [
              [ "Period", period_label ],
              [ "Currency", @report.currency ],
              [ "Generated", Exports::PdfTheme.format_time(generated_at, @report.hotel.hotel_time_zone) ],
              [ "Prepared by", @printed_by ]
            ]
          }
        ]
      end

      def balance_metrics
        [
          [ "Opening Balance", money(@report.opening_balance) ],
          [ "Closing Balance", money(@report.closing_balance) ]
        ]
      end

      def add_aging(builder)
        aging = @report.aging
        builder.add_table(
          section_title: "Invoice Aging",
          section_meta: "As of #{format_date(@report.end_date)}",
          headers: [ "Current", "1-30", "31-60", "61-90", "90+", "Total" ],
          rows: [
            [
              aging.current,
              aging.days_1_30,
              aging.days_31_60,
              aging.days_61_90,
              aging.days_over_90,
              aging.total
            ].map { |amount| money_cell(amount) }
          ],
          numeric_columns: (0..5).to_a,
          total_row: nil,
          empty_message: "No invoice aging is available."
        )
      end

      def add_summary_ledger(builder)
        builder.add_table(
          section_title: "Statement Activity",
          headers: [ "Date", "Type", "Reference", "Description", "Due", "Debit", "Credit", "Balance" ],
          rows: @report.ledger_rows.map { |row| ledger_row(row) },
          numeric_columns: [ 5, 6, 7 ],
          total_row: nil,
          empty_message: "No AR activity in this statement period.",
          column_widths: proportional_widths(builder.content_width, [ 8, 7, 10, 27, 8, 13, 13, 14 ]),
          density: :dense
        )
      end

      def ledger_row(row)
        [
          format_date(row.effective_date),
          escape(row.record_type),
          escape(row.reference),
          escape(row.description),
          row.due_on ? format_date(row.due_on) : "-",
          money_cell(row.debit),
          money_cell(row.credit, credit: row.credit.to_d.positive?),
          money_cell(row.balance, balance: true)
        ]
      end

      def add_invoice_details(builder)
        if @report.invoice_details.empty?
          return builder.add_table(
            section_title: "Invoice Details",
            headers: [],
            rows: [],
            numeric_columns: [],
            total_row: nil,
            empty_message: "No invoices issued in this statement period.",
            show_header: false
          )
        end

        @report.invoice_details.each do |detail|
          add_invoice_detail_header(builder, detail)
          add_invoice_detail_lines(builder, detail)
        end
      end

      def add_invoice_detail_header(builder, detail)
        builder.add_table(
          section_title: "Invoice Details",
          section_meta: detail.bill_no,
          headers: [ "Billing Name", "Bill No", "Check In", "Check Out", "Balance" ],
          rows: [
            [
              escape(detail.billing_name),
              escape(detail.bill_no),
              detail.check_in ? format_date(detail.check_in.to_date) : "-",
              detail.check_out ? format_date(detail.check_out.to_date) : "-",
              money_cell(detail.balance)
            ]
          ],
          numeric_columns: [ 4 ],
          total_row: nil,
          empty_message: "No invoice details are available.",
          column_widths: proportional_widths(builder.content_width, [ 32, 16, 16, 16, 20 ])
        )
      end

      def add_invoice_detail_lines(builder, detail)
        builder.add_table(
          section_title: nil,
          headers: [ "Date", "Room", "Description", "Charges", "Credits", "Balance" ],
          rows: detail.line_items.map { |item| invoice_line_row(detail, item) },
          numeric_columns: [ 3, 4, 5 ],
          total_row: nil,
          empty_message: "No invoice line items are available.",
          column_widths: proportional_widths(builder.content_width, [ 10, 14, 40, 12, 12, 12 ])
        )
      end

      def invoice_line_row(detail, item)
        [
          format_date(item.date),
          escape(detail.room_label),
          escape(item.description),
          money_cell(item.charge),
          money_cell(item.credit, credit: item.credit.to_d.positive?),
          money_cell(item.balance, balance: true)
        ]
      end

      def add_statement_summary(builder)
        width = builder.content_width * 0.52
        builder.add_table(
          section_title: "Statement Summary (#{@report.currency})",
          headers: [],
          rows: statement_summary_rows,
          numeric_columns: [ 1 ],
          total_row: nil,
          empty_message: "No statement summary is available.",
          column_widths: [ width * 0.62, width * 0.38 ],
          row_variants: { 3 => :subtotal },
          position: :right,
          width: width,
          show_header: false
        )
      end

      def statement_summary_rows
        [
          [ "Opening Balance", summary_money_cell(@report.opening_balance) ],
          [ "Invoices", summary_money_cell(@report.period_invoices) ],
          [ "Payments", summary_money_cell(-@report.period_payments) ],
          [ "Closing Balance", summary_money_cell(@report.closing_balance) ],
          [ "Unapplied Credit", summary_money_cell(-@report.unapplied_credit) ]
        ]
      end

      def money_cell(amount, credit: false, balance: false)
        value = amount.to_d
        color = if credit || (balance && value.negative?)
          Exports::PdfTheme::COLORS[:primary]
        else
          Exports::PdfTheme::COLORS[:ink]
        end
        { content: value.zero? ? "-" : format_amount(value), text_color: color }
      end

      def summary_money_cell(amount)
        value = amount.to_d
        color = value.negative? ? Exports::PdfTheme::COLORS[:primary] : Exports::PdfTheme::COLORS[:ink]
        { content: money(value), text_color: color }
      end

      def proportional_widths(width, shares)
        widths = shares.map { |share| width * share / shares.sum.to_f }
        widths[-1] += width - widths.sum
        widths
      end

      def money(amount) = "#{@report.currency} #{format_amount(amount)}"

      def format_amount(amount) = Exports::PdfTheme.money(amount)

      def format_date(date) = Exports::PdfTheme.format_date(date)

      def escape(value) = CGI.escapeHTML(value.to_s.presence || "-")
    end
  end
end
