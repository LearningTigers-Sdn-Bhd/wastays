# frozen_string_literal: true

module HotelPortal
  module Reports
    class PoliceReportExportTable
      HEADERS = [ "Guest / booking reference", "Room", "Nights stayed", "Nationality", "Gender", "Date of birth", "Address", "Contact", "Scheduled check-in", "Actual check-in", "Scheduled check-out", "Actual check-out", "Status" ].freeze
      PDF_HEADERS = [ "Guest", "Room", "Nights stayed", "Guest details", "Contact", "Scheduled check-in", "Actual check-in", "Scheduled check-out", "Actual check-out", "Status" ].freeze

      def initialize(report:) = @report = report
      def headers = HEADERS
      def rows = @report.rows.map { |row| [ [ row[:guest_name], row[:confirmation_token] ].join("\n"), *row.values_at(:room_number, :nights_stayed, :nationality, :gender, :date_of_birth, :address, :contact, :scheduled_check_in, :actual_check_in, :scheduled_check_out, :actual_check_out, :status) ] }
      def pdf_headers = PDF_HEADERS

      def pdf_rows
        @report.rows.map do |row|
          [
            [ row[:guest_name], row[:confirmation_token] ].join("\n"),
            row[:room_number],
            row[:nights_stayed],
            [ [ row[:nationality], row[:gender] ].reject { |value| value == "-" }.join(" · "), row[:date_of_birth] ].compact_blank.join("\n"),
            [ row[:contact], row[:address] ].reject { |value| value == "-" }.join("\n"),
            row[:scheduled_check_in],
            row[:actual_check_in],
            row[:scheduled_check_out],
            row[:actual_check_out],
            row[:status]
          ]
        end
      end

      private
    end
  end
end
