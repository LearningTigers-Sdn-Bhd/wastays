# frozen_string_literal: true

require "cgi"
require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

# Guest-facing reservation voucher. It wears the shared print design system but
# draws its own body: the QR identity, projected booking charges and policy are not
# the tabular period-report shape owned by PdfReportBuilder.
module Reports
  module Bookings
    class GenerateVoucher
      THEME = HotelPortal::Reports::Exports::PdfTheme
      FIXED_COLUMN_WIDTHS = { date: 64, code: 76, quantity: 28, money: 66, gross: 70 }.freeze
      SUMMARY_WIDTH_FRACTION = 0.48
      SUMMARY_LABEL_FRACTION = 0.62

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
        @records = Reports::Bookings::GenerateVoucherRecords.new(booking).call
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)
        frame = build_frame(pdf)

        frame.draw_header
        HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(@records.party_blocks)
        draw_charges(pdf)
        draw_payments(pdf)
        draw_summary(pdf)
        draw_special_requests(pdf)
        draw_policies(pdf)
        draw_closing_notes(pdf)
        frame.stamp_page_furniture
        pdf.render
      end

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

      def draw_special_requests(pdf)
        return if @records.special_requests.blank?

        draw_prose_section(pdf, "Special requests", @records.special_requests)
      end

      def draw_policies(pdf)
        cancellation = @records.cancellation
        return unless cancellation.present?

        draw_prose_section(
          pdf,
          "Property policies",
          "Identification is required at check-in. Local government taxes may apply."
        )
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

        text = notes.map { |note| "- #{note}" }.join("\n")
        ensure_block_fits(pdf, text, heading: nil)
        draw_muted_line(pdf, text)
        pdf.move_down THEME::SPACE[:lg]
      end

      def draw_closing_notes(pdf)
        instruction = "Please present this voucher at check-in. This is an electronically generated document - no signature required."
        disclosure = @records.tourism_tax_disclosure
        height = pdf.height_of(instruction, size: THEME::TYPE[:small])
        height += pdf.height_of(disclosure, size: THEME::TYPE[:micro], leading: 2) + THEME::SPACE[:sm] if disclosure.present?
        pdf.start_new_page if pdf.cursor < height + THEME::SPACE[:lg]

        if disclosure.present?
          draw_muted_line(pdf, disclosure)
          pdf.move_down THEME::SPACE[:sm]
        end
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text instruction, size: THEME::TYPE[:small], style: :italic
        pdf.fill_color THEME::COLORS[:ink]
      end

      def draw_prose_section(pdf, heading, text)
        ensure_block_fits(pdf, text, heading: heading)
        pdf.fill_color THEME::COLORS[:ink]
        pdf.text heading, size: THEME::TYPE[:heading], style: :bold
        pdf.move_down THEME::SPACE[:sm]
        pdf.text text, size: THEME::TYPE[:body], leading: 2
        pdf.move_down THEME::SPACE[:lg]
      end

      def ensure_block_fits(pdf, text, heading:)
        height = pdf.height_of(text, size: THEME::TYPE[:body], leading: 2)
        if heading.present?
          height += pdf.height_of(heading, size: THEME::TYPE[:heading], style: :bold) + THEME::SPACE[:sm]
        end
        pdf.start_new_page if pdf.cursor < height + THEME::SPACE[:lg]
      end

      def draw_muted_line(pdf, text)
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text text, size: THEME::TYPE[:micro], leading: 2
        pdf.fill_color THEME::COLORS[:ink]
      end

      def money_or_dash(value) = value.nil? ? "-" : @records.money(value)

      def credit_amount(value) = "(#{@records.money(value.to_d.abs)})"
    end
  end
end
