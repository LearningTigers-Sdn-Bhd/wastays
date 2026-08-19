# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    # Guest-facing reservation voucher: proof that a room is owed, on these dates, under
    # these terms. It is presented at check-in, which is why it states no money.
    #
    # What is charged, what has been paid and what is still owed are GenerateBookingSummary's
    # subject. A guest handing this over at the desk should not be handing over their
    # balance with it.
    #
    # Wears the shared print design system but draws its own body: the QR identity and the
    # policy blocks are not the tabular period-report shape owned by PdfReportBuilder.
    class GenerateVoucher
      THEME = HotelPortal::Reports::Exports::PdfTheme

      CLOSING_NOTE = "Please present this voucher at check-in. This is an electronically generated document - no signature required."
      POLICY_NOTE = "Identification is required at check-in. Local government taxes may apply."

      class TitleAccessory
        QR_SIZE = 64
        ITEM_GAP = THEME::SPACE[:sm]

        def initialize(pdf:, token:, badge:)
          @pdf = pdf
          @badge = badge
          @qr = qr_image_io(token)
          @pdf_badge = HotelPortal::Reports::Exports::PdfBadge.new(pdf: pdf)
        end

        def width = [ QR_SIZE, @pdf_badge.width(@badge.fetch(:label)) ].max

        def height = @pdf_badge.height + ITEM_GAP + QR_SIZE

        def draw(at:)
          left, top = at
          badge_width = @pdf_badge.width(@badge.fetch(:label))
          @pdf_badge.draw(
            label: @badge.fetch(:label),
            at: [ left + width - badge_width, top ],
            variant: @badge.fetch(:variant, :neutral)
          )
          @pdf.image @qr,
            at: [ left + width - QR_SIZE, top - @pdf_badge.height - ITEM_GAP ],
            width: QR_SIZE,
            height: QR_SIZE
        end

        private

        def qr_image_io(token)
          png = RQRCode::QRCode.new(token).as_png(
            bit_depth: 1,
            border_modules: 2,
            color_mode: ChunkyPNG::COLOR_GRAYSCALE,
            color: "black",
            file: nil,
            fill: "white",
            module_px_size: 6,
            resize_exactly_to: false,
            resize_gte_to: false
          )
          StringIO.new(png.to_s)
        end
      end

      def initialize(booking)
        @booking = booking
        @records = Reports::Bookings::GenerateReservationRecords.new(booking: booking).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)
        frame = render_into(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

      # Draws one voucher into a document it does not own and hands back the frame, so a pack
      # can stack many of them and stamp the furniture once at the end. The single voucher
      # and its page inside a pack come out of this same path, so a reprinted room is
      # identical to the page it was reprinted from.
      def render_into(pdf)
        frame = build_frame(pdf)
        frame.draw_header
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_special_requests(pdf)
        draw_policies(pdf)
        draw_closing_note(pdf)
        frame
      end

      def confirmation_token = @records.confirmation_token

      private

      def document_info
        {
          Title: "Booking Voucher - #{@records.confirmation_token}",
          Author: "WAStays",
          Creator: "WAStays",
          CreationDate: Time.current
        }
      end

      def build_frame(pdf)
        accessory = TitleAccessory.new(
          pdf: pdf,
          token: @records.confirmation_token,
          badge: @records.status_badge
        )
        HotelPortal::Reports::Exports::PdfReportFrame.new(
          pdf: pdf,
          hotel: @records.hotel,
          eyebrow: "Booking voucher",
          report_name: @records.reservation_number,
          subtitle: "Confirmation #{@records.confirmation_token}",
          metadata: [],
          confidential: false,
          title_accessory: accessory
        )
      end

      def draw_special_requests(pdf)
        prose(pdf).draw(@records.special_requests, heading: "Special requests")
      end

      def draw_policies(pdf)
        cancellation = @records.cancellation
        return unless cancellation.present?

        prose(pdf).draw(POLICY_NOTE, heading: "Property policies")
        draw_cancellation_table(pdf, cancellation.rows) if cancellation.rows.any?
        draw_cancellation_notes(pdf, cancellation)
      end

      def draw_cancellation_table(pdf, rows)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
          section_title: "Cancellation policy",
          headers: [ "If cancelled", "Charge" ],
          rows: rows.map { |row| [ row.window, row.charge ] },
          numeric_columns: [],
          total_row: nil,
          empty_message: "No cancellation tiers are configured.",
          column_widths: [ 0.62, 0.38 ].map { |fraction| pdf.bounds.width * fraction }
        )
      end

      def draw_cancellation_notes(pdf, cancellation)
        notes = [
          cancellation.refund_note,
          cancellation.description,
          cancellation.structured? ? nil : cancellation.legacy_text
        ].compact_blank
        return if notes.empty?

        prose(pdf).draw_muted(notes.map { |note| "- #{note}" }.join("\n"))
      end

      def draw_closing_note(pdf)
        prose(pdf).draw_closing(CLOSING_NOTE)
      end

      def prose(pdf) = HotelPortal::Reports::Exports::PdfProseBlock.new(pdf: pdf)
    end
  end
end
