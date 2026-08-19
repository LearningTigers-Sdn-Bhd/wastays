# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    # Attached to the confirmation email and reachable from the guest and public booking
    # pages. It states what was booked and what it is expected to cost.
    #
    # It is not evidence of payment: a receipt is issued per payment received and carries
    # its own number, which is what PaymentReceiptPdfService draws. This document says only
    # that the reservation exists.
    #
    # Wears the shared print design system (DESIGN.md §12) but draws its own body: the
    # parties it names do not fit a metadata strip, and its line items are the booked
    # position rather than the tabular period report PdfReportBuilder owns.
    class GenerateConfirmation
      THEME = HotelPortal::Reports::Exports::PdfTheme

      NIGHTS_WIDTH = 60
      AMOUNT_WIDTH = 96
      CLOSING_NOTE = "This document confirms the reservation and is not a payment receipt. " \
        "It is electronically generated - no signature required."

      def initialize(booking)
        @booking = booking
        @records = Reports::Bookings::GenerateReservationRecords.new(booking: booking).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)
        frame = build_frame(pdf)

        frame.draw_header
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_line_items(pdf)
        draw_closing_notes(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

      private

      def document_info
        {
          Title: "Booking Confirmation - #{@records.confirmation_token}",
          Author: "WAStays",
          Creator: "WAStays",
          CreationDate: Time.current
        }
      end

      # The confirmation code is the identity the guest quotes, so it is the title; the
      # internal reservation number goes underneath it. The parties go in blocks of their
      # own, so the frame draws no metadata strip above them.
      def build_frame(pdf)
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @records.hotel,
          eyebrow: "Booking confirmation",
          report_name: @records.confirmation_token,
          subtitle: "Reservation #{@records.reservation_number}",
          badge: @records.status_badge,
          metadata: [],
          # Goes to the guest, not into the hotel's filing cabinet.
          confidential: false
        )
      end

      # One row per room plus the taxes that the booking total actually includes. Tourism
      # tax is excluded from both, and says so in the closing notes, so the rows here always
      # sum to the total printed beneath them.
      def draw_line_items(pdf)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Booked items",
          headers: [ "Description", "Nights", "Amount (#{@records.currency})" ],
          rows: room_rows + tax_rows,
          numeric_columns: [ 1, 2 ],
          total_row: [ "Booking total", nil, @records.money(@records.total_due) ],
          empty_message: "No items are recorded for this reservation.",
          column_widths: column_widths(pdf)
        )
      end

      def room_rows
        @booking.booking_rooms.includes(:room_type).map do |room|
          [ room_name(room), nights.to_s, @records.money(room.subtotal) ]
        end
      end

      def tax_rows
        Array(@booking.tax_lines).map { |line| line.to_h.stringify_keys }.filter_map do |line|
          next if Booking.tourism_tax_line?(line) || line["amount"].to_d.zero?

          [ line["name"].presence || "Tax / charge", "-", @records.money(line["amount"]) ]
        end
      end

      def room_name(room) = room.room_type_snapshot.to_h["name"].presence || room.room_type.name

      def nights = (@booking.check_out.to_date - @booking.check_in.to_date).to_i

      def column_widths(pdf)
        [ pdf.bounds.width - NIGHTS_WIDTH - AMOUNT_WIDTH, NIGHTS_WIDTH, AMOUNT_WIDTH ]
      end

      def draw_closing_notes(pdf)
        disclosure = @records.tourism_tax_disclosure
        height = pdf.height_of(CLOSING_NOTE, size: THEME::TYPE[:small])
        height += pdf.height_of(disclosure, size: THEME::TYPE[:micro], leading: 2) + THEME::SPACE[:sm] if disclosure.present?
        pdf.start_new_page if pdf.cursor < height + THEME::SPACE[:lg]

        if disclosure.present?
          pdf.fill_color THEME::COLORS[:muted]
          pdf.text disclosure, size: THEME::TYPE[:micro], leading: 2
          pdf.move_down THEME::SPACE[:sm]
        end
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text CLOSING_NOTE, size: THEME::TYPE[:small], style: :italic
        pdf.fill_color THEME::COLORS[:ink]
      end
    end
  end
end
