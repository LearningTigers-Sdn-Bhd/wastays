# frozen_string_literal: true

require "cgi"
require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    # What a reservation is expected to cost, what has been paid against it, and what is
    # left. The money half of what the voucher used to carry.
    #
    # These are booked amounts, taken from the reservation's own snapshots. The invoice is
    # built from posted folio charges, and the two diverge as soon as anything is posted
    # during the stay — an early departure, a late checkout, a minibar. That is why the page
    # opens on a band saying which of the two this is: whoever is holding it has to know it
    # is not the final bill before they read a number off it.
    #
    # A group settles one position, so a group gets one summary rather than one per room.
    class GenerateBookingSummary
      THEME = HotelPortal::Reports::Exports::PdfTheme

      FIXED_COLUMN_WIDTHS = { date: 64, code: 76, quantity: 28, money: 66, gross: 70 }.freeze
      SUMMARY_WIDTH_FRACTION = 0.48
      SUMMARY_LABEL_FRACTION = 0.62

      NOTICE_LABEL = "BOOKED POSITION"
      NOTICE_NOTE = "These are the amounts agreed when the reservation was made. Charges posted during " \
        "the stay are billed on the invoice, which is the final bill."

      def initialize(booking: nil, group_booking: nil)
        @records = Reports::Bookings::GenerateReservationRecords.new(
          booking: booking,
          group_booking: group_booking
        ).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)
        frame = build_frame(pdf)

        frame.draw_header
        draw_notice(pdf)
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_charges(pdf)
        draw_payments(pdf)
        draw_summary(pdf)
        draw_closing_notes(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

      private

      def document_info
        {
          Title: "Booking Summary - #{@records.confirmation_token}",
          Author: "WAStays",
          Creator: "WAStays",
          CreationDate: Time.current
        }
      end

      def build_frame(pdf)
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @records.hotel,
          eyebrow: @records.group? ? "Group booking summary" : "Booking summary",
          report_name: @records.reservation_number,
          subtitle: "Confirmation #{@records.confirmation_token}",
          badge: @records.status_badge,
          metadata: [],
          # Goes to whoever is settling, not into the hotel's filing cabinet.
          confidential: false
        )
      end

      # Ahead of the party blocks, so it is read before any number on the page is.
      def draw_notice(pdf)
        HotelPortal::Reports::Exports::PdfNoticeBand.new(pdf: pdf)
          .draw(label: NOTICE_LABEL, note: NOTICE_NOTE, variant: :info)
      end

      def draw_charges(pdf)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Charges",
          headers: [
            "Date", "Code", "Description", "Qty",
            "Net (#{@records.currency})", "Charges (#{@records.currency})", "Gross (#{@records.currency})"
          ],
          rows: @records.charge_rows.map { |row| charge_row(row) },
          numeric_columns: [ 3, 4, 5, 6 ],
          total_row: [ nil, nil, "Total due", nil, nil, nil, @records.money(@records.total_due) ],
          empty_message: "No reservation charges are available.",
          column_widths: charge_column_widths(pdf),
          density: :dense
        )
      end

      def draw_payments(pdf)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Payments",
          headers: [ "Date", "Code", "Description", "Amount (#{@records.currency})" ],
          rows: @records.payment_rows.map { |row| payment_row(row) },
          numeric_columns: [ 3 ],
          total_row: [ nil, nil, "Total payments", credit_amount(@records.total_payments) ],
          empty_message: "No payments have been recorded for this reservation.",
          column_widths: payment_column_widths(pdf),
          density: :dense
        )
      end

      def charge_row(row)
        [
          row.date,
          row.code,
          description_cell(row.description, row.secondary_description),
          row.quantity,
          money_or_dash(row.net),
          money_or_dash(row.charges),
          money_or_dash(row.gross)
        ]
      end

      def payment_row(row)
        [
          row.date,
          row.code,
          description_cell(row.description, row.secondary_description),
          row.amount.positive? ? credit_amount(row.amount) : @records.money(row.amount)
        ]
      end

      def description_cell(description, secondary_description)
        content = CGI.escapeHTML(description.to_s)
        if secondary_description.present?
          content += "\n<font size='#{THEME::TYPE[:micro]}'>#{CGI.escapeHTML(secondary_description.to_s)}</font>"
        end
        { content: content, inline_format: true }
      end

      def charge_column_widths(pdf)
        fixed = FIXED_COLUMN_WIDTHS
        described = pdf.bounds.width - fixed[:date] - fixed[:code] - fixed[:quantity] -
          (fixed[:money] * 2) - fixed[:gross]
        [ fixed[:date], fixed[:code], described, fixed[:quantity], fixed[:money], fixed[:money], fixed[:gross] ]
      end

      def payment_column_widths(pdf)
        fixed = FIXED_COLUMN_WIDTHS
        [ fixed[:date], fixed[:code], pdf.bounds.width - fixed[:date] - fixed[:code] - fixed[:gross], fixed[:gross] ]
      end

      def draw_summary(pdf)
        rows = @records.summary_rows
        width = pdf.bounds.width * SUMMARY_WIDTH_FRACTION
        label_width = (width * SUMMARY_LABEL_FRACTION).floor

        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Summary (#{@records.currency})",
          headers: [ "", "" ],
          rows: rows.map { |row| [ row.label, row.amount.nil? ? "" : @records.money(row.amount) ] },
          numeric_columns: [ 1 ],
          total_row: nil,
          empty_message: "No amounts to summarise.",
          column_widths: [ label_width, width - label_width ],
          row_variants: rows.each_with_index.to_h { |row, index| [ index, row.variant ] }.compact,
          position: :right,
          show_header: false
        )
      end

      # Tourism tax sits outside the booking total, so it is disclosed here rather than
      # printed as a charge that would not sum into it.
      def draw_closing_notes(pdf)
        prose = HotelPortal::Reports::Exports::PdfProseBlock.new(pdf: pdf)
        prose.draw_muted(@records.tourism_tax_disclosure, trailing: THEME::SPACE[:sm])
      end

      def money_or_dash(value) = value.nil? ? "-" : @records.money(value)

      def credit_amount(value) = "(#{@records.money(value.to_d.abs)})"
    end
  end
end
