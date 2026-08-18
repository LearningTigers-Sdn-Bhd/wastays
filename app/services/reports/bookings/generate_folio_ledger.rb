# frozen_string_literal: true

require "csv"
require "cgi"
require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    class GenerateFolioLedger
      THEME = HotelPortal::Reports::Exports::PdfTheme

      # Landscape, and still seven columns wide, so the table takes the dense step of
      # the scale rather than tightening its columns.
      FIXED_COLUMN_WIDTHS = { code: 58, date: 62, source: 80, money: 74 }.freeze

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

      # Wears the shared print design system (DESIGN.md §12). It draws its own body rather
      # than going through PdfReportBuilder because its facts do not fit one metadata strip.
      def generate_pdf
        pdf = Prawn::Document.new(
          page_size: "A4",
          page_layout: :landscape,
          margin: THEME::PAGE_MARGIN,
          info: {
            Title: pdf_title,
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )
        THEME.configure_font(pdf)
        frame = HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: hotel,
          # The folio reference is the title; the eyebrow says what the reference belongs to.
          eyebrow: "Folio ledger",
          report_name: folio_reference,
          metadata: identity_pairs
        )

        frame.draw_header
        HotelPortal::Reports::Exports::PdfDetailGrid.new(pdf: pdf).draw(account_pairs)
        draw_transactions(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

      private

      attr_reader :booking, :folio

      def hotel = folio.hotel

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

      # Who and what the ledger is for goes in the frame's strip; how the account itself is
      # filed goes in the grid below it. Blank pairs are dropped by both, so an unlabelled
      # folio costs a column rather than printing a dash.
      def identity_pairs
        [
          [ "Booking ref", booking.confirmation_token ],
          [ "Guest", booking.guest_name ],
          [ "Room / type", room_summary ],
          [ "Stay", stay_dates ]
        ]
      end

      def account_pairs
        [
          [ "Account ref", folio_account_reference ],
          [ "Window", folio_window_label ],
          [ "Status", folio.status.to_s.titleize ],
          [ "Currency", currency ],
          [ "Printed by", printed_by ],
          [ "Generated", THEME.format_time(Time.current, hotel.hotel_time_zone) ]
        ]
      end

      def draw_transactions(pdf)
        ledger = ledger_rows
        totals = ledger_totals(ledger)

        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Ledger transactions",
          headers: [
            "Code", "Date", "Description / Reference", "Source",
            "Debit\n(#{currency})", "Credit\n(#{currency})", "Balance\n(#{currency})"
          ],
          rows: ledger.map { |row| transaction_row(row) },
          numeric_columns: [ 4, 5, 6 ],
          # The label sits in the description column rather than the first one: code is 58pt
          # wide, and a label that wraps to two lines reads as two rows.
          total_row: [
            "", "", "FOLIO TOTAL", "",
            format_money(totals[:debit]), format_money(totals[:credit]),
            format_money(totals[:balance], blank_zero: false)
          ],
          empty_message: "No transactions have been posted to this folio.",
          column_widths: transaction_column_widths(pdf),
          density: :dense
        )
      end

      def transaction_row(row)
        [
          row[:code].to_s.presence || "-",
          row[:date],
          description_cell(row),
          row[:source].to_s.presence || "-",
          format_money(row[:debit]),
          format_money(row[:credit]),
          format_money(row[:balance], blank_zero: false)
        ]
      end

      def transaction_column_widths(pdf)
        fixed = FIXED_COLUMN_WIDTHS
        [
          fixed[:code], fixed[:date],
          pdf.bounds.width - fixed[:code] - fixed[:date] - fixed[:source] - (fixed[:money] * 3),
          fixed[:source], fixed[:money], fixed[:money], fixed[:money]
        ]
      end

      def ledger_rows
        balance = 0.to_d
        transactions.map do |transaction|
          debit, credit = debit_credit_for(transaction)
          balance += debit - credit
          {
            code: transaction_code(transaction),
            date: THEME.format_date(transaction.posting_date),
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

        transaction.posted_transaction_code.presence || transaction.category.to_s.upcase
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
          transaction.posted_transaction_code.presence || transaction.category.to_s.upcase
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

        transaction.posted_transaction_code_name.presence || transaction.category.to_s.humanize
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

      # The only cell that carries more than one value: the reference sits under the
      # description a step down the scale rather than taking a column of its own.
      def description_cell(row)
        content = escape(row[:description].to_s.presence || "-")
        content += "\n<font size='#{THEME::TYPE[:micro]}'>#{escape(row[:reference])}</font>" if row[:reference].present?
        { content: content, inline_format: true }
      end

      def format_money(amount, blank_zero: true)
        amount = amount.to_d
        return "-" if blank_zero && amount.zero?
        return "(#{THEME.money(amount.abs)})" if amount.negative?

        THEME.money(amount)
      end

      def csv_money(amount)
        format("%.2f", amount.to_d)
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
        dates = [ booking.check_in, booking.check_out ].map { |date| THEME.format_date(date) }
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
