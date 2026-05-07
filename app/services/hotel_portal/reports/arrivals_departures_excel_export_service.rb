# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class ArrivalsDeparturesExcelExportService
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
            <Worksheet ss:Name="Arrivals">
              <Table>
                #{build_arrivals_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="Departures">
              <Table>
                #{build_departures_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def build_arrivals_rows
        rows = []
        rows << spreadsheet_row([ "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Pre-checkin Status", "Guarantee Method", "Deposit Status", "Notes" ])
        @report.arrivals.each do |row|
          rows << spreadsheet_row([
            row[:guest_name],
            row[:confirmation_token],
            row[:room_details],
            row[:room_numbers],
            row[:stay_dates],
            row[:pre_checkin_status],
            row[:guarantee_method_status],
            row[:deposit_status],
            row[:latest_note]
          ])
        end
        rows.join("\n")
      end

      def build_departures_rows
        rows = []
        rows << spreadsheet_row([ "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Notes" ])
        @report.departures.each do |row|
          rows << spreadsheet_row([
            row[:guest_name],
            row[:confirmation_token],
            row[:room_details],
            row[:room_numbers],
            row[:stay_dates],
            row[:departure_status],
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
    end
  end
end
