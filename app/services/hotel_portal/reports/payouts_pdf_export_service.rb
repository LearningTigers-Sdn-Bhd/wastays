# frozen_string_literal: true

module HotelPortal
  module Reports
    class PayoutsPdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(
          hotel: @hotel, title: "Weekly Settlements", subtitle: subtitle,
          period_label: period_label, period_label_title: "Payout cycle",
          prepared_by: @prepared_by, page_layout: :landscape
        )
        builder.add_header
        @report.paid? ? add_paid_content(builder) : add_upcoming_content(builder)
        builder.render
      end

      private

      def add_upcoming_content(builder)
        builder.add_summary([
          [ "Upcoming Amount", amount_label(@report.upcoming_total) ],
          [ "Processing Amount", amount_label(@report.processing_total) ],
          [ "Combined Amount", amount_label(@report.upcoming_total + @report.processing_total) ]
        ])
        builder.add_table(
          section_title: "Upcoming Settlements", headers: PayoutsCsvExportService::UPCOMING_HEADERS,
          rows: @report.upcoming_rows.map { |row| [ row[:booking_reference], datetime(row[:checked_out_at]), row[:status].to_s.titleize, currency, money(row[:net_amount]) ] },
          numeric_columns: [ 4 ], total_row: [ "TOTAL", nil, nil, currency, money(@report.upcoming_total) ],
          empty_message: "No upcoming settlements found."
        )
        builder.add_table(
          section_title: "Processing Batches", headers: PayoutsCsvExportService::BATCH_HEADERS,
          rows: @report.processing_rows.map { |row| [ date(row[:period_start]), date(row[:period_end]), row[:status].to_s.titleize, row[:reference].presence || "-", currency, money(row[:net_amount]) ] },
          numeric_columns: [ 5 ], total_row: [ "TOTAL", nil, nil, nil, currency, money(@report.processing_total) ],
          empty_message: "No payout batches are processing."
        )
      end

      def add_paid_content(builder)
        builder.add_summary([ [ "Paid Batches", @report.paid_rows.size.to_s ], [ "Paid Amount", amount_label(@report.paid_total) ] ])
        builder.add_table(
          section_title: "Paid History", headers: PayoutsCsvExportService::PAID_HEADERS,
          rows: @report.paid_rows.map { |row| [ date(row[:period_start]), date(row[:period_end]), datetime(row[:settled_at]), row[:status].to_s.titleize, row[:reference].presence || "-", currency, money(row[:net_amount]) ] },
          numeric_columns: [ 6 ], total_row: [ "TOTAL", nil, nil, nil, nil, currency, money(@report.paid_total) ],
          empty_message: "No paid settlements found for this period."
        )
      end

      def subtitle
        @report.paid? ? "Paid History" : "Upcoming & Processing"
      end

      def period_label
        return "Current payout cycle" unless @report.paid? && @report.paid_start_date
        return date(@report.paid_start_date) unless @report.paid_end_date && @report.paid_end_date != @report.paid_start_date

        "#{date(@report.paid_start_date)} - #{date(@report.paid_end_date)}"
      end

      def amount_label(value) = "#{currency} #{money(value)}"
      def money(value) = format("%.2f", value.to_d)
      def date(value) = value&.strftime("%d %b %Y") || "-"
      def datetime(value) = value&.strftime("%d %b %Y %H:%M") || "-"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
