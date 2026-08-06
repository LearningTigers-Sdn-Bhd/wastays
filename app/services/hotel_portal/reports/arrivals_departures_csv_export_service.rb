# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesCsvExportService
      BIBO_HEADERS = [ "Guest Name", "Room Number", "Arrival Date", "Departure Date", "Arrival Time", "Departure Time" ].freeze

      # The sectioned surfaces (screen tables, sheets, PDF pages) split by meal, so
      # the flat CSV names each row's entitlements in a column instead.
      MEAL_PREP_COLUMNS = [ "Guest Name", "Pax", "Room Number", "Transfer", "Transfer Date", "Transfer Time" ].freeze
      MEAL_PREP_HEADERS = (MEAL_PREP_COLUMNS + [ "Meal Preps" ]).freeze

      def initialize(report:, tab: "arrivals")
        @report = report
        @tab = tab.to_s
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << export_headers
          export_rows.each { |row| csv << row.map { |value| @csv.text(value) } }
          csv << export_total_row.map { |value| @csv.text(value) } if export_total_row
        end
      end

      def export_headers = headers_for_active_tab

      def export_rows
        return bibo_leg_rows if bibo_leg
        return bibo_rows if @tab == "bibo"
        return @report.records.map { |row| meal_prep_row(row) + [ row[:meals].join(", ") ] } if @tab == "meal_prep"

        rows_for_active_tab.map { |row| values_for_active_tab(row) }
      end

      # Meal prep is the one tab that totals: the builders style this as a real
      # total row rather than another body row.
      def export_total_row
        return nil unless @tab == "meal_prep"

        [ "Total Pax", @report.total_pax ] + Array.new(export_headers.size - 2)
      end

      # Ordered like the screen table; the meal column is the caller's to append.
      def meal_prep_row(row)
        [ row[:guest_name], row[:pax], row[:room_number], row[:type], row[:transfer_date], row[:formatted_boat_time] ]
      end

      # A single-leg export is about that leg, so it carries only its own date and
      # time rather than a paired row with the other half struck out.
      def bibo_leg
        return nil unless @tab == "bibo" && @report.respond_to?(:leg) && @report.leg.present?

        @bibo_leg ||= @report.sections.first
      end

      def bibo_leg_headers = [ "Guest Name", "Room Number", bibo_leg[:date_header], bibo_leg[:time_header] ]

      private

      def bibo_leg_rows
        bibo_leg[:rows].map { |row| [ row[:guest_name], row[:room_number], row[bibo_leg[:date_key]], row[:boat_time] ] }
      end

      # The report lists each direction on its own; the flat exports pair the two
      # legs of a guest back onto a single row so both times sit side by side.
      def bibo_rows
        paired = {}

        @report.boat_ins.each do |row|
          paired[row[:booking_guest_id]] = bibo_row_stem(row) + [ row[:boat_time], "—" ]
        end

        @report.boat_outs.each do |row|
          existing = paired[row[:booking_guest_id]]
          if existing
            existing[BIBO_HEADERS.index("Departure Time")] = row[:boat_time]
          else
            paired[row[:booking_guest_id]] = bibo_row_stem(row) + [ "—", row[:boat_time] ]
          end
        end

        paired.values
      end

      def bibo_row_stem(row) = [ row[:guest_name], row[:room_number], row[:arrival_date], row[:departure_date] ]

      def headers_for_active_tab
        return bibo_leg_headers if bibo_leg
        return BIBO_HEADERS if @tab == "bibo"
        return MEAL_PREP_HEADERS if @tab == "meal_prep"

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
