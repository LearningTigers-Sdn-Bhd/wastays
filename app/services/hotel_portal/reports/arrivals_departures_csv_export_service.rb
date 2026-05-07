# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class ArrivalsDeparturesCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [
            "Section",
            "Guest Name",
            "Booking Ref",
            "Rooms",
            "Room Numbers",
            "Stay",
            "Pre-checkin Status",
            "Guarantee Method",
            "Deposit Status",
            "Departure Status",
            "Notes"
          ]

          @report.arrivals.each do |row|
            csv << [
              "Arrival",
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
            ]
          end

          @report.departures.each do |row|
            csv << [
              "Departure",
              row[:guest_name],
              row[:confirmation_token],
              row[:room_details],
              row[:room_numbers],
              row[:stay_dates],
              nil,
              nil,
              nil,
              row[:departure_status],
              row[:latest_note]
            ]
          end
        end
      end
    end
  end
end
