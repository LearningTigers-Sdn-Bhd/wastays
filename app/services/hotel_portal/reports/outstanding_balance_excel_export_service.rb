# frozen_string_literal: true

module HotelPortal
  module Reports
    class OutstandingBalanceExcelExportService
      HEADERS = [ "Guest Name", "Booking Ref", "Stay", "Rooms", "Room Numbers", "Payment Status", "Outstanding Amount", "Notes" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Outstanding Balance Report", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Outstanding Balances", widths: [ 24, 18, 24, 24, 16, 18, 20, 30 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: [ [ "Outstanding Bookings", @report.totals[:booking_count], nil ], [ "Outstanding Amount", @report.totals[:outstanding_amount], currency ] ])
          builder.add_table(
            sheet: sheet, section_title: "Outstanding Bookings", headers: HEADERS,
            rows: @report.rows.map { |row| row.values_at(:guest_name, :confirmation_token, :stay_dates, :room_details, :room_numbers, :payment_status, :outstanding_amount, :latest_note) },
            column_types: %i[text text text text text text money text],
            total_row: [ "TOTAL", nil, nil, nil, nil, nil, @report.totals[:outstanding_amount], nil ],
            empty_message: "No outstanding bookings for the selected period."
          )
        end
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
