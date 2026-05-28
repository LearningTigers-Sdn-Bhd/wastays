# frozen_string_literal: true

require "csv"
require "cgi"
require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class FinancialBreakdownExportService
      def initialize(bookings:, hotel:, start_date:, end_date:)
        @bookings = bookings
        @hotel = hotel
        @start_date = start_date
        @end_date = end_date
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          csv << [ "Booking Ref", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Margin", "Net", "Currency" ]
          @bookings.each do |booking|
            gross = booking.booking_folio&.folio_transactions&.select { |t| t.charge? || t.adjustment? }&.sum(&:amount) || 0.to_d
            taxes = booking.tax_total || 0.to_d
            margin = booking.margin_amount || 0.to_d
            csv << [ booking.confirmation_token, booking.guest_name, booking.status, booking.check_in, booking.check_out, money(gross), money(taxes), money(margin), money(gross - margin), booking.currency ]
          end
        end
      end

      def generate_xls
        <<~XML
          <?xml version="1.0"?>
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Financial Breakdown"><Table>#{rows}</Table></Worksheet>
          </Workbook>
        XML
      end

      def generate_pdf
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])
        draw_header(pdf)
        pdf.text "Financial Breakdown", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "#{@start_date.strftime('%d %b %Y')} - #{@end_date.strftime('%d %b %Y')}", size: 10
        pdf.move_down 12

        table_rows = [ [ "Booking Ref", "Guest", "Status", "Gross", "Taxes", "Margin", "Net" ] ] + @bookings.map do |b|
          [ b.confirmation_token, b.guest_name, b.status, money(b.total_amount), money(b.tax_total), money(b.margin_amount), money(b.net_amount) ]
        end
        pdf.table(table_rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) { row(0).font_style = :bold }
        pdf.render
      end

      private

      def rows
        result = []
        result << row([ "Booking Ref", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Margin", "Net", "Currency" ])
        @bookings.each do |b|
          gross = b.booking_folio&.folio_transactions&.select { |t| t.charge? || t.adjustment? }&.sum(&:amount) || 0.to_d
          taxes = b.tax_total || 0.to_d
          margin = b.margin_amount || 0.to_d
          result << row([ b.confirmation_token, b.guest_name, b.status, b.check_in, b.check_out, money(gross), money(taxes), money(margin), money(gross - margin), b.currency ])
        end
        result.join("\n")
      end

      def row(values)
        "<Row>#{values.map { |v| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(v.to_s)}</Data></Cell>) }.join}</Row>"
      end

      def money(value)
        format("%.2f", value.to_d)
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
