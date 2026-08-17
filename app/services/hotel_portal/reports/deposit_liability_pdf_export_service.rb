# frozen_string_literal: true

module HotelPortal
  module Reports
    class DepositLiabilityPdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(
          hotel: @hotel, title: "Deposit Liability Report",
          period_label: @report.as_of_date.strftime("%d %b %Y"), period_label_title: "As of date",
          prepared_by: @prepared_by, page_layout: :landscape
        )
        builder.add_header
        builder.add_summary([ [ "Bookings", @report.totals[:booking_count].to_s ], [ "Booking Payments", amount(:booking_payment_amount) ], [ "Earned", amount(:earned_amount) ], [ "Remaining Liability", amount(:remaining_liability) ] ])
        builder.add_table(
          section_title: "Open Deposit Liabilities", headers: DepositLiabilityExcelExportService::HEADERS,
          rows: @report.rows.map { |row| [ row[:guest_name], row[:confirmation_token], row[:stay_dates], row[:booking_status], row[:room_details], row[:folio_number], money(row[:booking_payment_amount]), money(row[:earned_amount]), money(row[:refund_amount]), money(row[:remaining_liability]), row[:latest_deposit_posting_date]&.strftime("%d %b %Y") || "-" ] },
          numeric_columns: [ 6, 7, 8, 9 ], total_row: [ "TOTAL", nil, nil, nil, nil, nil, *@report.totals.values_at(:booking_payment_amount, :earned_amount, :refund_amount, :remaining_liability).map { |value| money(value) }, nil ],
          empty_message: "No deposit liabilities for this as-of date."
        )
        builder.render
      end

      private

      def amount(key) = "#{currency} #{money(@report.totals[key])}"
      def money(value) = Exports::PdfTheme.money(value)
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
