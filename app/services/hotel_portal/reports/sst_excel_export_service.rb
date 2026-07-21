# frozen_string_literal: true

module HotelPortal
  module Reports
    class SstExcelExportService
      include SimpleExcelReport

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        build_workbook do
          sheet = add_report_sheet(title: "SST", column_count: 7, widths: [ 16, 22, 14, 14, 16, 14, 14 ], period_label: period_label)

          rows = @report.rows.map do |row|
            [
              row[:invoice_number],
              row[:guest_name],
              row[:check_in].strftime("%d %b %Y"),
              row[:check_out].strftime("%d %b %Y"),
              decimal(row[:taxable_amount]),
              decimal(row[:sst_amount]),
              decimal(row[:total_amount])
            ]
          end

          add_data_table(
            sheet,
            headers: [ "Invoice / Ref", "Guest Name", "Check-In", "Check-Out", "Taxable Amount (MYR)", "SST 8% (MYR)", "Total (MYR)" ],
            rows: rows,
            money_columns: [ 4, 5, 6 ],
            total_row: [ "TOTAL (#{@report.totals[:booking_count]} bookings)", nil, nil, nil, decimal(@report.totals[:taxable_amount]), decimal(@report.totals[:sst_amount]), decimal(@report.totals[:total_amount]) ]
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
