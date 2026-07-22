# frozen_string_literal: true

module HotelPortal
  module Reports
    class PayoutsExcelExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(
          hotel: @hotel,
          title: "Weekly Settlements",
          period_label: period_label
        ).generate do |builder|
          @report.paid? ? add_paid_sheet(builder) : add_upcoming_sheet(builder)
        end
      end

      private

      def add_upcoming_sheet(builder)
        sheet = builder.add_sheet(name: "Upcoming & Processing", widths: [ 22, 20, 16, 12, 16 ])
        builder.add_header(sheet: sheet, subtitle: "Upcoming & Processing")
        builder.add_summary(sheet: sheet, metrics: [
          [ "Upcoming Amount", @report.upcoming_total, currency ],
          [ "Processing Amount", @report.processing_total, currency ],
          [ "Combined Amount", @report.upcoming_total + @report.processing_total, currency ]
        ])
        builder.add_table(
          sheet: sheet, section_title: "Upcoming Settlements",
          headers: PayoutsCsvExportService::UPCOMING_HEADERS,
          rows: @report.upcoming_rows.map { |row| [ row[:booking_reference], row[:checked_out_at], row[:status].to_s.titleize, currency, row[:net_amount] ] },
          column_types: %i[text datetime text text money],
          total_row: [ "TOTAL", nil, nil, currency, @report.upcoming_total ],
          empty_message: "No upcoming settlements found."
        )
        builder.add_table(
          sheet: sheet, section_title: "Processing Batches",
          headers: PayoutsCsvExportService::BATCH_HEADERS,
          rows: @report.processing_rows.map { |row| [ row[:period_start], row[:period_end], row[:status].to_s.titleize, row[:reference].presence || "-", currency, row[:net_amount] ] },
          column_types: %i[date date text text text money],
          total_row: [ "TOTAL", nil, nil, nil, currency, @report.processing_total ],
          empty_message: "No payout batches are processing."
        )
      end

      def add_paid_sheet(builder)
        sheet = builder.add_sheet(name: "Paid History", widths: [ 15, 15, 20, 14, 20, 12, 16 ], orientation: :landscape)
        builder.add_header(sheet: sheet, subtitle: "Paid History")
        builder.add_summary(sheet: sheet, metrics: [
          [ "Paid Batches", @report.paid_rows.size, nil ],
          [ "Paid Amount", @report.paid_total, currency ]
        ])
        builder.add_table(
          sheet: sheet, section_title: "Paid History",
          headers: PayoutsCsvExportService::PAID_HEADERS,
          rows: @report.paid_rows.map { |row| [ row[:period_start], row[:period_end], row[:settled_at], row[:status].to_s.titleize, row[:reference].presence || "-", currency, row[:net_amount] ] },
          column_types: %i[date date datetime text text text money],
          total_row: [ "TOTAL", nil, nil, nil, nil, currency, @report.paid_total ],
          empty_message: "No paid settlements found for this period."
        )
      end

      def period_label
        return "Current payout cycle" unless @report.paid? && @report.paid_start_date
        return @report.paid_start_date.strftime("%d %b %Y") unless @report.paid_end_date && @report.paid_end_date != @report.paid_start_date

        "#{@report.paid_start_date.strftime('%d %b %Y')} - #{@report.paid_end_date.strftime('%d %b %Y')}"
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end
    end
  end
end
