# frozen_string_literal: true

module HotelPortal
  module Reports
    class NonNationalExcelExportService
      include SimpleExcelReport

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        build_workbook do
          sheet = add_report_sheet(title: "Non-National", column_count: 7, widths: [ 22, 14, 14, 30, 14, 12, 14 ], period_label: period_label)

          rows = @report.rows.map do |row|
            [
              row[:guest_name],
              row[:guest_country],
              row[:date_of_birth]&.strftime("%d %b %Y"),
              row[:guest_home_address],
              row[:check_in].strftime("%d %b %Y"),
              row[:checked_in_at]&.strftime("%I:%M %p"),
              row[:check_out].strftime("%d %b %Y")
            ]
          end

          add_data_table(
            sheet,
            headers: [ "Full Name", "Nationality", "Date of Birth", "Home Address", "Check In Date", "Check In Time", "Check Out Date" ],
            rows: rows,
            total_row: [ "TOTAL (#{@report.totals[:guest_count]} guests, #{@report.totals[:nights]} nights)", nil, nil, nil, nil, nil, nil ]
          )
        end
      end

      private

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end
    end
  end
end
