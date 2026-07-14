# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class ArrivalsDeparturesExcelExportService
      XML_HEADER = %(<?xml version="1.0"?>).freeze

      def initialize(report:, tab: "arrivals")
        @report = report
        @tab = tab.to_s
      end

      def generate
        <<~XML
          #{XML_HEADER}
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
            xmlns:o="urn:schemas-microsoft-com:office:office"
            xmlns:x="urn:schemas-microsoft-com:office:excel"
            xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="#{worksheet_name}">
              <Table>
                #{build_rows_for_active_tab}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def build_rows_for_active_tab
        rows = []
        rows << spreadsheet_row(headers_for_active_tab)
        if @tab == "bibo"
          @report.boat_ins.each do |row|
            rows << spreadsheet_row([
              "Boat Arrival",
              row[:guest_name],
              row[:confirmation_token],
              row[:room_type],
              row[:room_number],
              row[:stay_dates],
              row[:boat_time]
            ])
          end
          @report.boat_outs.each do |row|
            rows << spreadsheet_row([
              "Boat Departure",
              row[:guest_name],
              row[:confirmation_token],
              row[:room_type],
              row[:room_number],
              row[:stay_dates],
              row[:boat_time]
            ])
          end
        else
          rows_for_active_tab.each do |row|
            rows << spreadsheet_row([
              row[:guest_name],
              row[:confirmation_token],
              row[:room_details],
              row[:room_numbers],
              row[:stay_dates],
              *status_columns_for_active_tab(row),
              row[:latest_note]
            ])
          end
        end
        rows.join("\n")
      end

      def worksheet_name
        return "Boat Transfers" if @tab == "bibo"

        {
          "arrivals" => "Arrivals",
          "in_house" => "In-House",
          "departures" => "Departures",
          "checkout" => "Checkout"
        }.fetch(@tab, "Arrivals")
      end

      def rows_for_active_tab
        case @tab
        when "in_house" then @report.in_house
        when "departures" then @report.departures
        when "checkout" then @report.checkout
        else @report.arrivals
        end
      end

      def headers_for_active_tab
        return [ "Type", "Guest Name", "Booking Ref", "Room Type", "Room Number", "Stay Dates", "Boat Time" ] if @tab == "bibo"
        return [ "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Pre-checkin Status", "Guarantee Method", "Deposit Status", "Notes" ] if @tab == "arrivals"
        return [ "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Boat Departure", "Notes" ] if @tab == "in_house"

        [ "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Notes" ]
      end

      def status_columns_for_active_tab(row)
        return [
          row[:pre_checkin_status],
          row[:guarantee_method_status],
          row[:deposit_status]
        ] if @tab == "arrivals"

        if @tab == "in_house"
          boat_dep_str = if row[:boat_departure].present?
            tz = @report.respond_to?(:hotel_time_zone) ? @report.hotel_time_zone : Time.zone.name
            boat_time = row[:boat_departure].in_time_zone(tz)
            "#{boat_time.strftime('%d %b %Y')}\n#{boat_time.strftime('%I:%M %p')}"
          else
            "—"
          end
          return [ row[:departure_status], boat_dep_str ]
        end

        [ row[:departure_status] ]
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
