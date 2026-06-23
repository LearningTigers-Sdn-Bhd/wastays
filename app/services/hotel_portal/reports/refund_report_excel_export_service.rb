# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class RefundReportExcelExportService
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
            <Worksheet ss:Name="Refund Records">
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
        rows << spreadsheet_row([ "Refund Count", @report.totals[:refund_count] ])
        rows << spreadsheet_row([ "Total Refund", money(@report.totals[:total_amount]) ])
        rows.join("\n")
      end

      def detail_rows
        rows = []
        rows << spreadsheet_row([ "Date", "Room", "Guest", "Booking Ref", "Refund Method", "Reference", "Status", "Reason", "Refund Amount" ])

        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:date].strftime("%Y-%m-%d"),
            row[:room],
            row[:guest_name],
            row[:booking_reference],
            row[:refund_method],
            row[:reference],
            row[:status],
            row[:reason],
            money(row[:refund_amount])
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
