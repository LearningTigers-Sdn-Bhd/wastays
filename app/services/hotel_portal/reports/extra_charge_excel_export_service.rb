# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class ExtraChargeExcelExportService
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
            <Worksheet ss:Name="#{sheet_name}">
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
        rows << spreadsheet_row([ "Tab", sheet_name ])
        rows << spreadsheet_row([ "Transactions", @report.totals[:transaction_count].to_s ])
        rows << spreadsheet_row([ "Total Amount (MYR)", money(@report.totals[:total_amount]) ])
        rows.join("\n")
      end

      def detail_rows
        rows = []
        rows << spreadsheet_row([ "Posting Date", "Booking Ref", "Folio Ref", "Guest Name", "Description", "Category", "Amount (MYR)" ])
        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:posting_date].strftime("%d %b %Y"),
            row[:booking_reference],
            row[:folio_number],
            row[:guest_name],
            row[:description],
            category_label(row[:category]),
            money(row[:amount])
          ])
        end
        rows << spreadsheet_row([ "TOTAL", nil, nil, nil, nil, @report.totals[:transaction_count].to_s, money(@report.totals[:total_amount]) ])
        rows.join("\n")
      end

      def sheet_name
        @report.active_tab == "fb" ? "F&B" : "Non-F&B"
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

      def category_label(value)
        value.to_s.upcase
      end
    end
  end
end
