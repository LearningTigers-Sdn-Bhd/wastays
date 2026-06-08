# frozen_string_literal: true

require "csv"
require "cgi"
require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class PayoutsExportService
      def initialize(hotel:, active_tab:, upcoming_bookings:, upcoming_payout_amount:, processing_batches:, payout_history:)
        @hotel = hotel
        @active_tab = active_tab
        @upcoming_bookings = upcoming_bookings
        @upcoming_payout_amount = upcoming_payout_amount.to_d
        @processing_batches = processing_batches
        @payout_history = payout_history
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          if @active_tab == "paid"
            csv << [ "Period", "Settled At", "Status", "Reference", "Net Amount" ]
            @payout_history.each do |batch|
              csv << [ "#{batch.period_start} - #{batch.period_end}", batch.payout_at, batch.status.titleize, batch.payout_reference, money(batch.amount) ]
            end
          else
            csv << [ "Booking Ref", "Checked Out At", "Status", "Net Amount" ]
            @upcoming_bookings.each do |booking|
              csv << [ booking.confirmation_token, booking.checked_out_at, booking.payout_status.titleize, money(booking.net_amount) ]
            end
          end
        end
      end

      def generate_xls
        <<~XML
          <?xml version="1.0"?>
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Payouts"><Table>#{rows}</Table></Worksheet>
          </Workbook>
        XML
      end

      def generate_pdf
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])
        draw_header(pdf)
        pdf.text "Weekly Settlements", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "Payout Type: #{payout_type_label}", size: 10
        pdf.move_down 12

        if @active_tab == "paid"
          rows = [ [ "Period", "Settled At", "Status", "Reference", "Net Amount" ] ] + @payout_history.map { |b| [ "#{b.period_start} - #{b.period_end}", b.payout_at&.strftime("%d %b %Y") || "Pending", b.status.titleize, b.payout_reference.presence || "-", money(b.amount) ] }
        else
          rows = [ [ "Booking Ref", "Checked Out At", "Status", "Net Amount" ] ] + @upcoming_bookings.map { |b| [ b.confirmation_token, b.checked_out_at&.strftime("%d %b %Y %I:%M %p") || "-", b.payout_status.titleize, money(b.net_amount) ] }
        end

        pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) { row(0).font_style = :bold }
        pdf.render
      end

      private

      def rows
        result = []
        if @active_tab == "paid"
          result << row([ "Period", "Settled At", "Status", "Reference", "Net Amount" ])
          @payout_history.each { |b| result << row([ "#{b.period_start} - #{b.period_end}", b.payout_at, b.status.titleize, b.payout_reference, money(b.amount) ]) }
        else
          result << row([ "Booking Ref", "Checked Out At", "Status", "Net Amount" ])
          @upcoming_bookings.each { |b| result << row([ b.confirmation_token, b.checked_out_at, b.payout_status.titleize, money(b.net_amount) ]) }
        end
        result.join("\n")
      end

      def row(values)
        "<Row>#{values.map { |v| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(v.to_s)}</Data></Cell>) }.join}</Row>"
      end

      def money(value)
        format("%.2f", value.to_d)
      end

      def payout_type_label
        return "Paid" if @active_tab == "paid"

        "Upcoming & Processing"
      end

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        end
      end
    end
  end
end
