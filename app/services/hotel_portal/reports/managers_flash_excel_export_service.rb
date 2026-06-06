# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class ManagersFlashExcelExportService
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
            <Worksheet ss:Name="Manager Flash Report">
              <Table>
                #{daily_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def summary_rows
        rows = []
        rows << spreadsheet_row([ "Metric", "Value" ])
        rows << spreadsheet_row([ "Rooms Sold", @report.totals[:rooms_sold] ])
        rows << spreadsheet_row([ "Rooms Available", @report.totals[:rooms_available] ])
        rows << spreadsheet_row([ "Occupancy %", percentage(@report.totals[:occupancy_rate]) ])
        rows << spreadsheet_row([ "Average Daily Rate (ADR)", money(@report.totals[:adr]) ])
        rows << spreadsheet_row([ "Revenue per Available Room (RevPAR)", money(@report.totals[:revpar]) ])
        rows << spreadsheet_row([ "Room Revenue", money(@report.totals[:room_revenue]) ])
        rows << spreadsheet_row([ "Tax", money(@report.totals[:tax_amount]) ])
        rows << spreadsheet_row([ "Total Revenue", money(@report.totals[:total_revenue]) ])
        rows.join("\n")
      end

      def daily_rows
        rows = []
        rows << spreadsheet_row([ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Room Revenue", "Tax", "Total Revenue" ])

        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:date].strftime("%Y-%m-%d"),
            row[:rooms_sold],
            row[:rooms_available],
            percentage(row[:occupancy_rate]),
            money(row[:adr]),
            money(row[:revpar]),
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

      def percentage(value)
        format("%.2f%%", value.to_d * 100)
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
