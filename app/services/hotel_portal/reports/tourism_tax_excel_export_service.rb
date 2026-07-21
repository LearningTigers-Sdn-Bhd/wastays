# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxExcelExportService
      include SimpleExcelReport

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        build_workbook do
          sheet = add_report_sheet(title: "Tourism Tax", column_count: 9, widths: [ 22, 14, 14, 12, 12, 8, 14, 16, 16 ], period_label: period_label)

          rows = @report.rows.map do |row|
            [
              row[:guest_name],
              row[:guest_country],
              row[:booking_reference],
              row[:check_in].strftime("%d %b %Y"),
              row[:check_out].strftime("%d %b %Y"),
              row[:nights],
              decimal(row[:tax_due]),
              decimal(row[:tax_collected]),
              row[:collection_status]
            ]
          end

          add_data_table(
            sheet,
            headers: [ "Guest Name", "Nationality", "Booking Ref", "Check In", "Check Out", "Nights", "Tax Due (MYR)", "Tax Collected (MYR)", "Collection Status" ],
            rows: rows,
            money_columns: [ 6, 7 ],
            total_row: [ "TOTAL (#{@report.totals[:guest_count]} guests)", nil, nil, nil, nil, nil, decimal(@report.totals[:total_due]), decimal(@report.totals[:total_collected]), nil ]
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
