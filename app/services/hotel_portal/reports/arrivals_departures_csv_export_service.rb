# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class ArrivalsDeparturesCsvExportService
      def initialize(report:, tab: "arrivals")
        @report = report
        @tab = tab.to_s
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << headers_for_active_tab
          if @tab == "bibo"
            @report.boat_ins.each do |row|
              csv << [ "Boat Arrival", row[:guest_name], row[:confirmation_token], row[:room_type], row[:room_number], row[:stay_dates], row[:boat_time] ]
            end
            @report.boat_outs.each do |row|
              csv << [ "Boat Departure", row[:guest_name], row[:confirmation_token], row[:room_type], row[:room_number], row[:stay_dates], row[:boat_time] ]
            end
          else
            rows_for_active_tab.each do |row|
              csv << values_for_active_tab(row)
            end
          end
        end
      end

      private

      def headers_for_active_tab
        return [ "Type", "Guest Name", "Booking Ref", "Room Type", "Room Number", "Stay Dates", "Boat Time" ] if @tab == "bibo"
        return [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Pre-checkin Status", "Guarantee Method", "Deposit Status", "Departure Status", "Notes" ] if @tab == "arrivals"

        [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Notes" ]
      end

      def rows_for_active_tab
        case @tab
        when "in_house" then @report.in_house
        when "departures" then @report.departures
        when "checkout" then @report.checkout
        else @report.arrivals
        end
      end

      def active_tab_label
        {
          "arrivals" => "Arrival",
          "in_house" => "In-House",
          "departures" => "Departure",
          "checkout" => "Checkout",
          "bibo" => "Boat Transfers"
        }.fetch(@tab, "Arrival")
      end

      def values_for_active_tab(row)
        return [
          active_tab_label,
          row[:guest_name],
          row[:confirmation_token],
          row[:room_details],
          row[:room_numbers],
          row[:stay_dates],
          row[:pre_checkin_status],
          row[:guarantee_method_status],
          row[:deposit_status],
          nil,
          row[:latest_note]
        ] if @tab == "arrivals"

        [
          active_tab_label,
          row[:guest_name],
          row[:confirmation_token],
          row[:room_details],
          row[:room_numbers],
          row[:stay_dates],
          row[:departure_status],
          row[:latest_note]
        ]
      end
    end
  end
end
