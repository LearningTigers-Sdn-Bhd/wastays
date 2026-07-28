# frozen_string_literal: true

require "csv"
require "cgi"
require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    class GenerateFolioLedger
      DARK_GREEN = "0a2e29"
      LIGHT_GRAY = "f9fafb"
      BORDER_GRAY = "e5e7eb"
      TEXT_PRIMARY = "111827"
      TEXT_MUTED = "6b7280"
      BOTTOM_MARGIN = 72
      FOOTER_Y = -26

      PAYMENT_SOURCE_LABELS = {
        "cash" => "Cash",
        "bank" => "Bank Transfer",
        "card" => "Card Terminal",
        "gateway" => "Gateway Manual Recovery",
        "ota" => "OTA Collected"
      }.freeze

      PAYMENT_REFERENCE_KEYS = [
        [ "receipt_reference", "Receipt" ],
        [ "bank_reference", "Bank Ref" ],
        [ "card_reference", "Card Ref" ],
        [ "gateway_reference", "Gateway Ref" ],
        [ "ota_reference", "OTA Ref" ],
        [ "reference", "Reference" ],
        [ "auth_code", "Auth" ],
        [ "authorization_code", "Auth" ],
        [ "gateway_payment_id", "Gateway Ref" ],
        [ "payment_transaction_id", "Gateway Ref" ],
        [ "refund_request_id", "Refund Ref" ]
      ].freeze

      CSV_HEADERS = [
        "Folio Account Reference",
        "Folio Reference",
        "Booking Ref",
        "Guest Name",
        "Room No / Type",
        "Stay Dates",
        "Folio Status",
        "Window",
        "Currency",
        "Code",
        "Posting Date",
        "Description",
        "Reference",
        "Source",
        "Debit",
        "Credit",
        "Balance"
      ].freeze

      def initialize(folio:, printed_by: nil)
        @folio = folio
        @booking = folio.booking
        @printed_by = printed_by
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          csv << CSV_HEADERS
          ledger_rows.each { |row| csv << csv_row_for(row) }
        end
      end

      def generate_pdf
        pdf = Prawn::Document.new(
          page_size: "A4",
          page_layout: :landscape,
          margin: [ 36, 32, BOTTOM_MARGIN, 32 ],
          info: {
            Title: pdf_title,
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        draw_header(pdf)
        pdf.move_down 14
        draw_metadata(pdf)
        pdf.move_down 14
        draw_transactions(pdf)
        draw_footer(pdf)
        pdf.render
      end

      private

      attr_reader :booking, :folio

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
        pdf.text "Folio Ledger", size: 18, style: :bold, align: :right
        pdf.move_down 12
        pdf.stroke_color DARK_GREEN
        pdf.line_width 0.5
        pdf.stroke_horizontal_rule
        pdf.line_width 1
        pdf.fill_color TEXT_PRIMARY
      end

      def transactions
        @transactions ||= folio.folio_transactions
                              .includes(:transaction_code, :user, :night_audit)
                              .order(:posting_date, :created_at, :id)
      end

      def csv_row_for(row)
        [
          folio_account_reference,
          folio_reference,
          booking.confirmation_token,
          booking.guest_name,
          room_summary,
          stay_dates,
          folio.status.to_s.titleize,
          folio_window_label,
          currency,
          row[:code],
          row[:posting_date]&.iso8601,
          row[:description],
          row[:reference].to_s,
          row[:source],
          csv_money(row[:debit]),
          csv_money(row[:credit]),
          csv_money(row[:balance])
        ]
      end

      def draw_metadata(pdf)
        rows = [
          [ { content: "FOLIO", colspan: 4, font_style: :bold, text_color: TEXT_PRIMARY } ],
          [ label_cell("Folio Account Reference"), value_cell(folio_account_reference), label_cell("Folio Reference"), value_cell(folio_reference) ],
          [ label_cell("Booking Ref"), value_cell(booking.confirmation_token), label_cell("Window"), value_cell(folio_window_label) ],
          [ label_cell("Guest Name"), value_cell(booking.guest_name), label_cell("Room No / Type"), value_cell(room_summary) ],
          [ label_cell("Stay Dates"), value_cell(stay_dates), label_cell("Folio Status"), value_cell(folio.status.to_s.titleize) ],
          [ label_cell("Currency"), value_cell(currency), label_cell(""), value_cell("") ]
        ]

        label_width = 95
        value_width = (pdf.bounds.width - (label_width * 2)) / 2.0
        pdf.table(rows, width: pdf.bounds.width, column_widths: [ label_width, value_width, label_width, value_width ]) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 8, 5, 8 ]
          cells.size = 8
          cells.inline_format = true
          row(0).background_color = LIGHT_GRAY
          row(0).padding = [ 6, 8, 6, 8 ]
        end
      end

      def draw_transactions(pdf)
        ledger = ledger_rows
        totals = ledger_totals(ledger)
        table_rows = [
          [
            header_cell("Code"),
            header_cell("Date"),
            header_cell("Description / Reference"),
            header_cell("Source"),
            header_cell("Debit\n(#{currency})", align: :right),
            header_cell("Credit\n(#{currency})", align: :right),
            header_cell("Balance\n(#{currency})", align: :right)
          ]
        ]

        table_rows += ledger.map do |row|
          [
            body_cell(row[:code], color: TEXT_MUTED),
            body_cell(row[:date], color: TEXT_MUTED),
            description_cell(row),
            body_cell(row[:source], color: TEXT_MUTED),
            money_cell(row[:debit]),
            money_cell(row[:credit]),
            money_cell(row[:balance], balance: true)
          ]
        end

        table_rows << [
          { content: "FOLIO TOTAL", colspan: 4, font_style: :bold, text_color: TEXT_PRIMARY, background_color: LIGHT_GRAY },
          money_cell(totals[:debit], bold: true, background_color: LIGHT_GRAY),
          money_cell(totals[:credit], bold: true, background_color: LIGHT_GRAY),
          money_cell(totals[:balance], bold: true, balance: true, background_color: LIGHT_GRAY)
        ]

        pdf.table(table_rows, width: pdf.bounds.width, header: true, column_widths: transaction_column_widths(pdf)) do
          cells.border_color = BORDER_GRAY
          cells.padding = [ 5, 6, 5, 6 ]
          cells.size = 7.5
          cells.inline_format = true
          row(0).background_color = LIGHT_GRAY
          row(0).font_style = :bold
        end
      end

      def transaction_column_widths(pdf)
        width = pdf.bounds.width
        [ 55, 58, width - 55 - 58 - 80 - 72 - 72 - 72, 80, 72, 72, 72 ]
      end

      def ledger_rows
        balance = 0.to_d
        transactions.map do |transaction|
          debit, credit = debit_credit_for(transaction)
          balance += debit - credit
          {
            code: transaction_code(transaction),
            date: transaction.posting_date&.strftime("%d %b %y"),
            posting_date: transaction.posting_date,
            description: display_description(transaction),
            reference: reference_text(transaction),
            source: source_label(transaction),
            debit: debit,
            credit: credit,
            balance: balance
          }
        end
      end

      def ledger_totals(rows)
        debit = rows.sum { |row| row[:debit] }
        credit = rows.sum { |row| row[:credit] }
        { debit: debit, credit: credit, balance: debit - credit }
      end

      def debit_credit_for(transaction)
        amount = transaction.amount.to_d
        case transaction.transaction_type
        when "charge"
          amount.negative? ? [ 0.to_d, amount.abs ] : [ amount.abs, 0.to_d ]
        when "payment"
          amount.negative? ? [ amount.abs, 0.to_d ] : [ 0.to_d, amount.abs ]
        when "adjustment"
          amount.negative? ? [ 0.to_d, amount.abs ] : [ amount.abs, 0.to_d ]
        else
          amount.negative? ? [ 0.to_d, amount.abs ] : [ amount.abs, 0.to_d ]
        end
      end

      def transaction_code(transaction)
        return payment_code(transaction) if transaction.payment?

        transaction.transaction_code&.code.presence || transaction.category.to_s.upcase
      end

      def payment_code(transaction)
        source = transaction.metadata.to_h["payment_source"].to_s
        case source
        when "cash" then "CASH"
        when "bank" then "BANK"
        when "card" then "CARD"
        when "gateway" then "GATEWAY"
        when "ota" then "OTA"
        else
          transaction.transaction_code&.code.presence || transaction.category.to_s.upcase
        end
      end

      def display_description(transaction)
        return payment_description(transaction) if transaction.payment?
        return "Reversal - #{transaction.description}" if transaction.reversal_of_transaction_id.present?

        transaction.description.to_s
      end

      def payment_description(transaction)
        label = payment_label(transaction)
        return "Refund - #{label}" if transaction.category == "refund"

        "Payment - #{label}"
      end

      def payment_label(transaction)
        source = transaction.metadata.to_h["payment_source"].presence
        return PAYMENT_SOURCE_LABELS[source] if PAYMENT_SOURCE_LABELS.key?(source)

        transaction.transaction_code&.name.presence || transaction.category.to_s.humanize
      end

      def reference_text(transaction)
        correction = correction_reference(transaction)
        return correction if correction.present?

        metadata = transaction.metadata.to_h
        PAYMENT_REFERENCE_KEYS.each do |key, label|
          value = metadata[key].presence || metadata.dig("source_references", key).presence
          return "#{label} #{value}" if value.present?
        end

        nil
      end

      def correction_reference(transaction)
        return if transaction.reversal_of_transaction_id.blank?

        parts = [ "Reversal of TRX-#{transaction.reversal_of_transaction_id}" ]
        reason = transaction.correction_reason.presence || transaction.metadata.to_h["override_reason"].presence
        parts << "Reason #{reason}" if reason.present?
        parts.join(" · ")
      end

      def source_label(transaction)
        return "Correction" if transaction.reversal_of_transaction_id.present?
        return "Night Audit" if transaction.night_audit_id.present? || transaction.metadata.to_h["posting_source"] == "night_audit"

        source = transaction.metadata.to_h["posting_source"].presence
        return source.to_s.titleize if source.present? && source != "staff"

        transaction.user_id.present? ? "Staff" : "System"
      end

      def label_cell(label)
        { content: label.to_s, text_color: TEXT_MUTED, font_style: :bold }
      end

      def value_cell(value)
        { content: escape(value.to_s.presence || "-"), text_color: TEXT_PRIMARY }
      end

      def header_cell(text, align: :left)
        { content: escape(text), text_color: TEXT_MUTED, align: align }
      end

      def body_cell(text, align: :left, color: TEXT_PRIMARY)
        { content: escape(text.to_s.presence || "-"), text_color: color, align: align }
      end

      def description_cell(row)
        content = escape(row[:description].to_s.presence || "-")
        content += "\n<font size='6.5'>#{escape(row[:reference])}</font>" if row[:reference].present?
        { content: content, inline_format: true, text_color: TEXT_PRIMARY }
      end

      def money_cell(amount, bold: false, balance: false, background_color: nil)
        {
          content: format_money(amount, blank_zero: !balance),
          align: :right,
          text_color: TEXT_PRIMARY,
          font_style: (bold ? :bold : nil),
          background_color: background_color
        }.compact
      end

      def format_money(amount, blank_zero: false)
        amount = amount.to_d
        return "-" if blank_zero && amount.zero?
        return "(#{format('%.2f', amount.abs)})" if amount.negative?

        format("%.2f", amount)
      end

      def csv_money(amount)
        format("%.2f", amount.to_d)
      end

      def draw_footer(pdf)
        pdf.repeat(:all) do
          pdf.stroke_color BORDER_GRAY
          pdf.line_width 0.5
          pdf.stroke_horizontal_line(pdf.bounds.left, pdf.bounds.right, at: FOOTER_Y + 14)

          pdf.bounding_box([ pdf.bounds.left, FOOTER_Y ], width: pdf.bounds.width - 88, height: 12) do
            pdf.fill_color TEXT_MUTED
            pdf.text printed_at_text, size: 7, align: :left
          end
        end

        pdf.number_pages "Page <page> of <total>",
          at: [ pdf.bounds.right - 75, FOOTER_Y ],
          size: 7,
          color: TEXT_MUTED
      end

      def printed_at_text
        "Printed at #{Time.current.strftime('%d %b %Y %H:%M')} by #{printed_by}"
      end

      def printed_by
        @printed_by.presence || transactions.filter_map(&:user).first&.name.presence || "-"
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end

      def pdf_title
        "Folio Ledger - #{folio_reference.presence || booking.confirmation_token}"
      end

      def room_number
        @room_number ||= booking.booking_rooms.first&.room_number.to_s
      end

      def room_summary
        rooms = booking.booking_rooms.includes(:room_type).map do |room|
          type_name = room.room_type_snapshot.to_h["name"].presence || room.room_type&.name
          [ room.room_number.presence, type_name.presence ].compact.join(" / ").presence
        end

        rooms.compact.presence&.join(", ") || "-"
      end

      def stay_dates
        dates = [ booking.check_in, booking.check_out ].map { |date| date&.strftime("%d %b %Y") }
        dates.all?(&:present?) ? dates.join(" - ") : "-"
      end

      def currency
        @currency ||= transactions.first&.currency.presence || booking.currency.presence || "MYR"
      end

      def folio_account_reference
        booking.folio_account_reference_display.presence || booking.formatted_folio_number.presence || "-"
      end

      def folio_reference
        folio&.folio_reference_display.presence || folio_account_reference
      end

      # The reference already has its own cells, so the window column only adds
      # value when a human labelled the folio.
      def folio_window_label
        folio&.label.presence || "—"
      end

      def tax_type_for(transaction)
        transaction.metadata.to_h["tax_line"]&.dig("type").to_s.presence ||
          (transaction.category == "tax" ? derive_tax_type(transaction) : "")
      end

      def derive_tax_type(transaction)
        description = transaction.description.to_s.downcase
        return "sst" if description.include?("sst") || description.include?("service tax")
        return "tourism_tax" if description.include?("tourism")

        "tax"
      end
    end
  end
end
