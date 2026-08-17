# frozen_string_literal: true

require "prawn"
require "prawn/table"

module NightAudits
  module Reporting
  class AuditPacketPdfExport
    def initialize(night_audit:, prepared_by:, generated_at: Time.current)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date
      @summary = night_audit.financial_summary
      @prepared_by = prepared_by
      @generated_at = generated_at
    end

    def generate
      pdf = Prawn::Document.new(page_size: "A4", margin: [ 40, 48, 42, 48 ])
      HotelPortal::Reports::Exports::PdfTheme.configure_font(pdf)
      frame = HotelPortal::Reports::Exports::PdfReportFrame.new(
        pdf: pdf,
        hotel: @hotel,
        report_name: "Night Audit Packet",
        period_label: @business_date.strftime("%d %b %Y"),
        period_label_title: "Business date",
        prepared_by: @prepared_by,
        generated_at: @generated_at
      ).freeze

      # Page 1: Daily Summary
      frame.draw_header
      draw_daily_summary(pdf)

      # Page 2: Manual Adjustments
      pdf.start_new_page
      draw_adjustments(pdf)

      # Page 3: Audit Exceptions & Blockers
      pdf.start_new_page
      draw_exceptions(pdf)

      frame.stamp_footer

      pdf.render
    end

    private

    def draw_daily_summary(pdf)
      pdf.text "Audit Completed: #{audit_completed_label}", size: 9, color: "64748B"
      pdf.move_down 16
      pdf.text "1. Daily Financial Summary", size: 14, style: :bold, color: "0F172A"
      pdf.move_down 12

      data = [
        [ "Metric", "Amount" ],
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

      pdf.table(data, width: pdf.bounds.width, cell_style: { border_color: "E2E8F0", border_width: 0.5, padding: [ 8, 12 ], size: 10, text_color: "334155" }) do
        cells.borders = [ :top, :bottom ]
        row(0).font_style = :bold
        row(0).background_color = "F8FAFC"
        row(0).text_color = "0F172A"
        row(0).borders = [ :bottom ]
        row(0).border_width = 1.5
        column(1).align = :right
        row(4).font_style = :bold
        row(4).text_color = "0F172A"
        row(4).background_color = "F8FAFC"
        row(5).borders = []
        row(5).height = 16
        row(8).font_style = :bold
        row(8).text_color = "0F172A"
        row(8).background_color = "F8FAFC"
        row(9).borders = []
        row(9).height = 16
        row(10).font_style = :bold
        row(10).text_color = "9A3412"
        row(10).background_color = "FFFBEB"
        row(10).borders = [ :top, :bottom ]
        row(10).border_color = "FDE68A"
      end

      pdf.move_down 32
    end

    def draw_adjustments(pdf)
      pdf.text "2. Manual Adjustments & Voids", size: 14, style: :bold, color: "0F172A"
      pdf.move_down 4
      pdf.text "Detailed record of staff interventions, rebates, and revenue corrections.", size: 9, color: "64748B"
      pdf.move_down 12

      adjustments = NightAudits::TransactionsForBusinessDate.call(hotel: @hotel, business_date: @business_date)
        .where(category: [ "adjustment", "discount", "correction", "write_off" ])
        .includes(:user, booking_folio: :booking)
        .order(:created_at)

      data = [ [ "Time", "Guest Name", "Conf #", "Category", "User", "Amount", "Reason" ] ]
      if adjustments.empty?
        data << [ { content: "No manual adjustments recorded for this business date.", colspan: 7, align: :center, font_style: :italic, text_color: "94A3B8" } ]
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

      pdf.table(data, width: pdf.bounds.width, cell_style: { border_color: "F1F5F9", border_width: 0.5, padding: [ 8, 8 ], size: 9, text_color: "475569" }) do
        cells.borders = [ :bottom ]
        row(0).font_style = :bold
        row(0).background_color = "F8FAFC"
        row(0).text_color = "0F172A"
        row(0).border_color = "E2E8F0"
        row(0).border_width = 1.5
        column(5).align = :right if adjustments.any?
        column(3).text_color = "D97706" if adjustments.any?
      end

      pdf.move_down 32
    end

    def draw_exceptions(pdf)
      pdf.text "3. Audit Exceptions & Blockers", size: 14, style: :bold, color: "0F172A"
      pdf.move_down 4
      pdf.text "Summary of operational discrepancies and unresolved tasks identified at audit close.", size: 9, color: "64748B"
      pdf.move_down 12

      exceptions = @night_audit.exceptions || {}
      blockers = @night_audit.blocked_details || {}

      # Render Blockers Table
      pdf.text "Audit Blockers", size: 11, style: :bold, color: "DC2626"
      pdf.move_down 6

      blocker_data = [ [ "Type", "Guest / Confirmation", "Reason" ] ]
      if blockers.any? { |_, items| items.any? }
        blockers.each do |type, items|
          items.each do |item|
            blocker_data << [
              type.humanize,
              "#{item['guest_name']} (#{item['confirmation_token']})",
              item["reason"]
            ]
          end
        end
      else
        blocker_data << [ { content: "No critical audit blockers were recorded.", colspan: 3, align: :center, font_style: :italic, text_color: "94A3B8" } ]
      end

      pdf.table(blocker_data, width: pdf.bounds.width, cell_style: { border_color: "FEE2E2", border_width: 0.5, padding: [ 8, 8 ], size: 9, text_color: "475569" }) do
        cells.borders = [ :bottom ]
        row(0).font_style = :bold
        row(0).background_color = "FEF2F2"
        row(0).text_color = "991B1B"
        row(0).border_color = "FECACA"
        row(0).border_width = 1.5
      end

      pdf.move_down 24

      # Render Exceptions Table
      pdf.text "Operational Warnings", size: 11, style: :bold, color: "D97706"
      pdf.move_down 6

      exception_data = [ [ "Type", "Guest / Confirmation", "Details" ] ]
      if exceptions.any? { |_, items| items.any? }
        exceptions.each do |type, items|
          items.each do |item|
            exception_data << [
              type.humanize,
              "#{item['guest_name'] || 'N/A'} (#{item['confirmation_token'] || 'N/A'})",
              item["reason"] || item["details"] || "General exception"
            ]
          end
        end
      else
        exception_data << [ { content: "No operational warnings were recorded.", colspan: 3, align: :center, font_style: :italic, text_color: "94A3B8" } ]
      end

      pdf.table(exception_data, width: pdf.bounds.width, cell_style: { border_color: "FEF3C7", border_width: 0.5, padding: [ 8, 8 ], size: 9, text_color: "475569" }) do
        cells.borders = [ :bottom ]
        row(0).font_style = :bold
        row(0).background_color = "FFFBEB"
        row(0).text_color = "92400E"
        row(0).border_color = "FDE68A"
        row(0).border_width = 1.5
      end
    end

    def money(value)
      format("MYR %.2f", value.to_d)
    end

    def audit_completed_label
      @night_audit.completed_at&.strftime("%d %b %Y %H:%M:%S %Z") || "N/A"
    end
  end
  end
end
