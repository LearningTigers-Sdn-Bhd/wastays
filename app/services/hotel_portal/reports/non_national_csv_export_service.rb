# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class NonNationalCsvExportService
      def initialize(report:)
        @report = report
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Full Name", "Nationality", "Home Address", "Check In Date", "Check In Time", "Check Out Date" ]

          @report.rows.each do |row|
            csv << [
              row[:guest_name],
              row[:guest_country],
              row[:guest_home_address],
              row[:check_in].strftime("%d %b %Y"),
              row[:checked_in_at]&.strftime("%I:%M %p"),
              row[:check_out].strftime("%d %b %Y")
            ]
          end

          csv << [ "TOTAL", nil, nil, nil, nil, nil ]
        end
      end
    end
  end
end
