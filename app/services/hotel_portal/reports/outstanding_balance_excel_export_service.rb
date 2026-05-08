# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class OutstandingBalanceExcelExportService
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
            <Worksheet ss:Name="Outstanding Balances">
              <Table>
                #{detail_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def summary_rows
        rows = []
        rows << spreadsheet_row([ "Metric", "Value" ])
        rows << spreadsheet_row([ "Outstanding Bookings", @report.totals[:booking_count] ])
        rows << spreadsheet_row([ "Outstanding Amount", money(@report.totals[:outstanding_amount]) ])
        rows.join("\n")
      end

      def detail_rows
        rows = []
        rows << spreadsheet_row([ "Guest Name", "Booking Ref", "Stay", "Rooms", "Room Numbers", "Payment Status", "Outstanding Amount", "Notes" ])

        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:guest_name],
            row[:confirmation_token],
            row[:stay_dates],
            row[:room_details],
            row[:room_numbers],
            row[:payment_status],
            money(row[:outstanding_amount]),
            row[:latest_note]
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
