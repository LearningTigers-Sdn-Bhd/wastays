# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesCsvExportService
      def initialize(report:, tab: "arrivals")
        @report = report
        @tab = tab.to_s
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << export_headers
          export_rows.each { |row| csv << row.map { |value| @csv.text(value) } }
        end
      end

      def export_headers = headers_for_active_tab

      def export_rows
        return @report.boat_ins.map { |row| [ "Boat-in", row[:guest_name], row[:confirmation_token], row[:room_type], row[:room_number], row[:stay_dates], row[:boat_time] ] } +
          @report.boat_outs.map { |row| [ "Boat-out", row[:guest_name], row[:confirmation_token], row[:room_type], row[:room_number], row[:stay_dates], row[:boat_time] ] } if @tab == "bibo"
        return @report.records.map { |row| [ row[:type], row[:guest_name], row[:confirmation_token], row[:pax], row[:room_type], row[:room_number], row[:formatted_boat_time] ] } +
          [ [], [ "", "", "", "", "", "Total Pax", @report.total_pax ] ] if @tab == "meal_prep"

        rows_for_active_tab.map { |row| values_for_active_tab(row) }
      end

      private

      def headers_for_active_tab
        return [ "Type", "Guest Name", "Booking Ref", "Room Type", "Room Number", "Stay Dates", "Boat Time" ] if @tab == "bibo"
        return [ "Type", "Guest Name", "Booking Ref", "Pax", "Room Type", "Room Number", "Boat Time" ] if @tab == "meal_prep"

        allow_boat = @report.respond_to?(:allow_boat_information) && @report.allow_boat_information

        if @tab == "arrivals"
          if allow_boat
            return [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Pre-checkin Status", "Guarantee Method", "Deposit Status", "Departure Status", "Boat-in", "Notes" ]
          else
            return [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Pre-checkin Status", "Guarantee Method", "Deposit Status", "Departure Status", "Notes" ]
          end
        end

        if @tab == "in_house" || @tab == "departures" || @tab == "checkout"
          if allow_boat
            return [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Boat-out", "Notes" ]
          else
            return [ "Section", "Guest Name", "Booking Ref", "Rooms", "Room Numbers", "Stay", "Departure Status", "Notes" ]
          end
        end

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
          "bibo" => "Boat Transfers",
          "meal_prep" => "Meal Prep"
        }.fetch(@tab, "Arrival")
      end

      def values_for_active_tab(row)
        allow_boat = @report.respond_to?(:allow_boat_information) && @report.allow_boat_information
        tz = @report.respond_to?(:hotel_time_zone) ? @report.hotel_time_zone : Time.zone.name

        if @tab == "arrivals"
          cols = [
            active_tab_label,
            row[:guest_name],
            row[:confirmation_token],
            row[:room_details],
            row[:room_numbers],
            row[:stay_dates],
            row[:pre_checkin_status],
            row[:guarantee_method_status],
            row[:deposit_status],
            nil
          ]
          if allow_boat
            boat_arr_str = if row[:boat_arrival].present?
              boat_time = row[:boat_arrival].in_time_zone(tz)
              "#{boat_time.strftime('%d %b %Y')} #{boat_time.strftime('%I:%M %p')}"
            else
              "—"
            end
            cols << boat_arr_str
          end
          cols << row[:latest_note]
          return cols
        end

        if @tab == "in_house" || @tab == "departures" || @tab == "checkout"
          if !allow_boat
            return [
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

          boat_dep_str = if row[:boat_departure].present?
            boat_time = row[:boat_departure].in_time_zone(tz)
            "#{boat_time.strftime('%d %b %Y')} #{boat_time.strftime('%I:%M %p')}"
          else
            "—"
          end
          return [
            active_tab_label,
            row[:guest_name],
            row[:confirmation_token],
            row[:room_details],
            row[:room_numbers],
            row[:stay_dates],
            row[:departure_status],
            boat_dep_str,
            row[:latest_note]
          ]
        end

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
