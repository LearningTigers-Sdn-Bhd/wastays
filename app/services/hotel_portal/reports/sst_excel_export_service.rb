# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class SstExcelExportService
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
            <Worksheet ss:Name="SST Report">
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
        rows << spreadsheet_row([ "Period", "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}" ])
        rows << spreadsheet_row([ "Bookings with SST", @report.totals[:booking_count].to_s ])
        rows << spreadsheet_row([ "Total Taxable Amount (MYR)", money(@report.totals[:taxable_amount]) ])
        rows << spreadsheet_row([ "Total SST Collected (MYR)", money(@report.totals[:sst_amount]) ])
        rows << spreadsheet_row([ "Grand Total (MYR)", money(@report.totals[:total_amount]) ])
        rows.join("\n")
      end

      def detail_rows
        rows = []
        rows << spreadsheet_row([ "Invoice / Ref", "Guest Name", "Check-In", "Check-Out", "Taxable Amount (MYR)", "SST 8% (MYR)", "Total (MYR)" ])

        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:invoice_number],
            row[:guest_name],
            row[:check_in].strftime("%d %b %Y"),
            row[:check_out].strftime("%d %b %Y"),
            money(row[:taxable_amount]),
            money(row[:sst_amount]),
            money(row[:total_amount])
          ])
        end

        rows << spreadsheet_row([
          "TOTAL", nil, nil, nil,
          money(@report.totals[:taxable_amount]),
          money(@report.totals[:sst_amount]),
          money(@report.totals[:total_amount])
        ])

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
