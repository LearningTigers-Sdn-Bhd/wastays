# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class DailyRevenueExcelExportService
      XML_HEADER = %(<?xml version="1.0"?>).freeze

      def initialize(report:)
        @report = report
      end

      def generate
        <<~XML
          #{XML_HEADER}
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
            xmlns:o="urn:schemas-microsoft-com:office:office"
            xmlns:x="urn:schemas-microsoft-com:office:excel"
            xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Summary">
              <Table>
                #{summary_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="Daily Revenue">
              <Table>
                #{daily_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="Revenue by Source">
              <Table>
                #{source_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def summary_rows
        rows = []
        rows << spreadsheet_row([ "Metric", "Value" ])
        rows << spreadsheet_row([ "Total Bookings", @report.totals[:booking_count] ])
        rows << spreadsheet_row([ "Room Revenue", money(@report.totals[:room_revenue]) ])
        rows << spreadsheet_row([ "Tax", money(@report.totals[:tax_amount]) ])
        rows << spreadsheet_row([ "Total Revenue", money(@report.totals[:total_revenue]) ])
        rows.join("\n")
      end

      def daily_rows
        rows = []
        rows << spreadsheet_row([ "Date", "Bookings", "Room Revenue", "Tax", "Total Revenue" ])
        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:date].strftime("%Y-%m-%d"),
            row[:booking_count],
            money(row[:room_revenue]),
            money(row[:tax_amount]),
            money(row[:total_revenue])
          ])
        end
        rows.join("\n")
      end

      def source_rows
        rows = []
        rows << spreadsheet_row([ "Source", "Bookings", "Room Revenue", "Tax", "Total Revenue" ])
        @report.source_rows.each do |row|
          rows << spreadsheet_row([
            row[:source],
            row[:booking_count],
            money(row[:room_revenue]),
            money(row[:tax_amount]),
            money(row[:total_revenue])
          ])
        end
        rows.join("\n")
      end

      def spreadsheet_row(values)
        cells = values.map do |value|
          escaped = CGI.escapeHTML(value.to_s)
          %(<Cell><Data ss:Type="String">#{escaped}</Data></Cell>)
        end.join

        %(<Row>#{cells}</Row>)
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
