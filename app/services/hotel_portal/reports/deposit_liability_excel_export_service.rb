# frozen_string_literal: true

module HotelPortal
  module Reports
    class DepositLiabilityExcelExportService
      HEADERS = [ "Guest Name", "Booking Ref", "Stay", "Status", "Rooms", "Folio", "Deposit Received", "Earned", "Refunds", "Remaining Liability", "Latest Deposit Date" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Deposit Liability Report", period_label: "As of #{@report.as_of_date.strftime('%d %b %Y')}").generate do |builder|
          sheet = builder.add_sheet(name: "Deposit Liability", widths: [ 22, 18, 24, 14, 22, 16, 18, 14, 14, 20, 20 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: summary_metrics)
          builder.add_note(sheet: sheet, text: DepositLiabilityReport::SCOPE_NOTE)
          builder.add_table(
            sheet: sheet, section_title: "Open Deposit Liabilities", headers: HEADERS,
            rows: @report.rows.map { |row| row.values_at(:guest_name, :confirmation_token, :stay_dates, :booking_status, :room_details, :folio_number, :booking_payment_amount, :earned_amount, :refund_amount, :remaining_liability, :latest_deposit_posting_date) },
            column_types: %i[text text text text text text money money money money date],
            total_row: [ "TOTAL", nil, nil, nil, nil, nil, *@report.totals.values_at(:booking_payment_amount, :earned_amount, :refund_amount, :remaining_liability), nil ],
            empty_message: "No deposit liabilities for this as-of date."
          )
        end
      end

      private

      def summary_metrics
        [ [ "Bookings", @report.totals[:booking_count], nil ], [ "Deposits Received", @report.totals[:booking_payment_amount], currency ], [ "Earned", @report.totals[:earned_amount], currency ], [ "Refunds", @report.totals[:refund_amount], currency ], [ "Remaining Liability", @report.totals[:remaining_liability], currency ] ]
      end

      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
