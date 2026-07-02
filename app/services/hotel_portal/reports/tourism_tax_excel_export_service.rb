# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class TourismTaxExcelExportService
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
            <Worksheet ss:Name="Tourism Tax">
              <Table>
                #{detail_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def summary_rows
        [
          spreadsheet_row([ "Metric", "Value" ]),
          spreadsheet_row([ "Period", period_label ]),
          spreadsheet_row([ "Guests", @report.totals[:guest_count].to_s ]),
          spreadsheet_row([ "Total Due (MYR)", money(@report.totals[:total_due]) ]),
          spreadsheet_row([ "Total Collected (MYR)", money(@report.totals[:total_collected]) ])
        ].join("\n")
      end

      def detail_rows
        rows = [ spreadsheet_row([ "Guest Name", "Nationality", "Booking Ref", "Check In", "Check Out", "Nights", "Tax Due (MYR)", "Tax Collected (MYR)", "Collection Status" ]) ]
        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:guest_name],
            row[:guest_country],
            row[:booking_reference],
            row[:check_in].strftime("%d %b %Y"),
            row[:check_out].strftime("%d %b %Y"),
            row[:nights].to_s,
            money(row[:tax_due]),
            money(row[:tax_collected]),
            row[:collection_status]
          ])
        end
        rows << spreadsheet_row([ "TOTAL", nil, nil, nil, nil, @report.totals[:guest_count].to_s, money(@report.totals[:total_due]), money(@report.totals[:total_collected]), nil ])
        rows.join("\n")
      end

      def period_label
        if @report.start_date == @report.end_date
          @report.start_date.strftime("%d %b %Y")
        else
          "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
        end
      end

      def spreadsheet_row(values)
        cells = values.map do |value|
          %(<Cell><Data ss:Type="String">#{CGI.escapeHTML(value.to_s)}</Data></Cell>)
        end.join

        %(<Row>#{cells}</Row>)
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
