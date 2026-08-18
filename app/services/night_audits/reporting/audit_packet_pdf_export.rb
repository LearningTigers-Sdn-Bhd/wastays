# frozen_string_literal: true

require "prawn"
require "prawn/table"

module NightAudits
  module Reporting
  class AuditPacketPdfExport
    THEME = HotelPortal::Reports::Exports::PdfTheme

    def initialize(night_audit:, prepared_by:, generated_at: Time.current)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date
      @summary = night_audit.financial_summary
      @prepared_by = prepared_by
      @generated_at = generated_at
    end

    def generate
      pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN)
      THEME.configure_font(pdf)
      frame = HotelPortal::Reports::Exports::PdfReportFrame.new(
        pdf: pdf,
        hotel: @hotel,
        report_name: "Night Audit Packet",
        period_label: THEME.format_date(@business_date),
        period_label_title: "Business date",
        prepared_by: @prepared_by,
        generated_at: @generated_at
      )

      # Page 1: Daily Summary
      frame.draw_header
      draw_daily_summary(pdf)

      # Page 2: Manual Adjustments
      pdf.start_new_page
      draw_adjustments(pdf)

      # Page 3: Audit Exceptions & Blockers
      pdf.start_new_page
      draw_exceptions(pdf)

      frame.stamp_page_furniture

      pdf.render
    end

    private

    def draw_daily_summary(pdf)
      pdf.fill_color THEME::COLORS[:muted]
      pdf.text "Audit Completed: #{audit_completed_label}", size: THEME::TYPE[:body]
      pdf.move_down THEME::SPACE[:lg]
      rows = [
        [ "Room Revenue", money(@summary.room_revenue) ],
        [ "Tax Revenue", money(@summary.tax_revenue) ],
        [ "No-Show Charges", money(@summary.no_show_charges) ],
        [ "Total Revenue", money(@summary.room_revenue + @summary.tax_revenue + @summary.no_show_charges) ],
        [ "", "" ],
        [ "Payments Received", money(@summary.payments_total) ],
        [ "Refunds Issued", money(@summary.refunds_total) ],
        [ "Net Money Flow", money(@summary.payments_total - @summary.refunds_total) ],
        [ "", "" ],
        [ "Total Manual Adjustments", money(@summary.adjustments_total) ]
      ]

      # Grouping is the point of this table: revenue and money flow each close on their own
      # subtotal, and the adjustments line is flagged because it is what the audit is for.
      HotelPortal::Reports::Exports::PdfDataTable.new(pdf: pdf).draw(
        section_title: "1. Daily Financial Summary",
        headers: [ "Metric", "Amount" ],
        rows: rows,
        numeric_columns: [ 1 ],
        total_row: nil,
        empty_message: "No financial activity recorded for this business date.",
        row_variants: { 3 => :subtotal, 4 => :spacer, 7 => :subtotal, 8 => :spacer, 9 => :alert }
      )
    end

    def draw_adjustments(pdf)
      draw_section_heading(
        pdf, "2. Manual Adjustments & Voids",
        "Detailed record of staff interventions, rebates, and revenue corrections."
      )

      adjustments = NightAudits::TransactionsForBusinessDate.call(hotel: @hotel, business_date: @business_date)
        .where(category: [ "adjustment", "discount", "correction", "write_off" ])
        .includes(:user, booking_folio: :booking)
        .order(:created_at)

      data = [ [ "Time", "Guest Name", "Conf #", "Category", "User", "Amount", "Reason" ] ]
      if adjustments.empty?
        data << [ empty_cell("No manual adjustments recorded for this business date.", 7) ]
      else
        adjustments.each do |adj|
          data << [
            adj.created_at.strftime("%H:%M"),
            adj.booking_folio.booking.guest_name.to_s.truncate(15),
            adj.booking_folio.booking.confirmation_token,
            adj.category.humanize,
            adj.user&.name.to_s.truncate(10),
            money(adj.amount),
            adj.metadata["reason"].to_s.truncate(25)
          ]
        end
      end

      table = build_table(pdf, data)
      if adjustments.any?
        table.column(5).align = :right
        table.column(3).text_color = THEME::COLORS[:warning]
        adjustments.each_with_index { |_, index| table.row(index + 1).background_color = THEME::COLORS[:stripe] if index.odd? }
      end
      table.draw
    end

    def draw_exceptions(pdf)
      draw_section_heading(
        pdf, "3. Audit Exceptions & Blockers",
        "Summary of operational discrepancies and unresolved tasks identified at audit close."
      )

      draw_issue_table(
        pdf, "Audit Blockers", THEME::COLORS[:danger], THEME::COLORS[:danger_light],
        [ "Type", "Guest / Confirmation", "Reason" ],
        blocker_rows, "No critical audit blockers were recorded."
      )
      pdf.move_down THEME::SPACE[:xl]
      draw_issue_table(
        pdf, "Operational Warnings", THEME::COLORS[:warning], THEME::COLORS[:warning_light],
        [ "Type", "Guest / Confirmation", "Details" ],
        exception_rows, "No operational warnings were recorded."
      )
    end

    def draw_issue_table(pdf, title, accent, accent_light, headers, rows, empty_message)
      pdf.fill_color accent
      pdf.text title, size: THEME::TYPE[:heading], style: :bold
      pdf.move_down THEME::SPACE[:sm]
      pdf.fill_color THEME::COLORS[:ink]

      data = [ headers ]
      data << [ empty_cell(empty_message, headers.size) ] if rows.empty?
      data.concat(rows)

      table = build_table(pdf, data, header_background: accent_light, header_text: accent)
      rows.each_index { |index| table.row(index + 1).background_color = THEME::COLORS[:stripe] if index.odd? }
      table.draw
    end

    def blocker_rows
      (@night_audit.blocked_details || {}).flat_map do |type, items|
        items.map do |item|
          [ type.humanize, "#{item['guest_name']} (#{item['confirmation_token']})", item["reason"] ]
        end
      end
    end

    def exception_rows
      (@night_audit.exceptions || {}).flat_map do |type, items|
        items.map do |item|
          [
            type.humanize,
            "#{item['guest_name'] || 'N/A'} (#{item['confirmation_token'] || 'N/A'})",
            item["reason"] || item["details"] || "General exception"
          ]
        end
      end
    end

    def draw_section_heading(pdf, title, description = nil)
      pdf.fill_color THEME::COLORS[:ink]
      pdf.text title, size: THEME::TYPE[:heading], style: :bold
      if description
        pdf.move_down THEME::SPACE[:xs]
        pdf.fill_color THEME::COLORS[:muted]
        pdf.text description, size: THEME::TYPE[:body]
      end
      pdf.move_down THEME::SPACE[:sm]
      pdf.fill_color THEME::COLORS[:ink]
    end

    # Header styling is applied after the table is built, matching PdfReportBuilder: the
    # row is measured at the larger body size, so a smaller header can only over-measure.
    def build_table(pdf, data, header_background: THEME::COLORS[:ink], header_text: THEME::COLORS[:white])
      table = pdf.make_table(
        data,
        width: pdf.bounds.width,
        cell_style: {
          size: THEME::TYPE[:body], padding: THEME::TABLE_CELL_PADDING,
          border_color: THEME::COLORS[:border], border_width: THEME::RULE_WIDTH,
          borders: [ :bottom ], text_color: THEME::COLORS[:ink], valign: :top
        }
      )
      table.row(0).style(
        background_color: header_background, text_color: header_text,
        font_style: :bold, size: THEME::TYPE[:small], borders: []
      )
      table
    end

    def empty_cell(message, colspan)
      {
        content: message, colspan: colspan, align: :center, font_style: :italic,
        text_color: THEME::COLORS[:muted]
      }
    end

    def money(value) = "MYR #{THEME.money(value)}"

    def audit_completed_label
      THEME.format_time(@night_audit.completed_at, @hotel.hotel_time_zone) || "N/A"
    end
  end
  end
end
