# frozen_string_literal: true

module HotelPortal
  module Reports
    class RefundReportExcelExportService
      HEADERS = [ "Date", "Room", "Guest", "Booking Ref", "Refund Method", "Reference", "Status", "Reason", "Refund Amount" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Refund Report", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Refund Records", widths: [ 15, 20, 22, 18, 20, 18, 15, 32, 18 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: [ [ "Refund Count", @report.totals[:refund_count], nil ], [ "Total Refund", @report.totals[:total_amount], currency ] ])
          builder.add_table(
            sheet: sheet, section_title: "Refund Records", headers: HEADERS,
            rows: @report.rows.map { |row| row.values_at(:date, :room, :guest_name, :booking_reference, :refund_method, :reference, :status, :reason, :refund_amount) },
            column_types: %i[date text text text text text text text money],
            total_row: [ "TOTAL", nil, nil, nil, nil, nil, nil, nil, @report.totals[:total_amount] ],
            empty_message: "No refund data for the selected period."
          )
        end
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
