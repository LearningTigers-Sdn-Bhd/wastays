# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class DepositLiabilityExcelExportService
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
            <Worksheet ss:Name="Deposit Liability">
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
        rows << spreadsheet_row([ "As Of Date", @report.as_of_date.iso8601 ])
        rows << spreadsheet_row([ "Bookings With Liability", @report.totals[:booking_count] ])
        rows << spreadsheet_row([ "Advance Deposits", money(@report.totals[:advance_deposit_amount]) ])
        rows << spreadsheet_row([ "Earned", money(@report.totals[:earned_amount]) ])
        rows << spreadsheet_row([ "Refunds", money(@report.totals[:refund_amount]) ])
        rows << spreadsheet_row([ "Remaining Liability", money(@report.totals[:remaining_liability]) ])
        rows.join("\n")
      end

      def detail_rows
        rows = []
        rows << spreadsheet_row([ "Guest Name", "Booking Ref", "Stay", "Status", "Rooms", "Folio", "Advance Deposit", "Earned", "Refunds", "Remaining Liability", "Latest Deposit Date" ])

        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:guest_name],
            row[:confirmation_token],
            row[:stay_dates],
            row[:booking_status],
            row[:room_details],
            row[:folio_number],
            money(row[:advance_deposit_amount]),
            money(row[:earned_amount]),
            money(row[:refund_amount]),
            money(row[:remaining_liability]),
            row[:latest_deposit_posting_date]&.iso8601
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
