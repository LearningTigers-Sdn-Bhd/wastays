# frozen_string_literal: true

module Reports
  module AccountsReceivable
    class GenerateAgentSummary
      Exports = HotelPortal::Reports::Exports

      def initialize(hotel:, report:, printed_by: nil)
        @hotel = hotel
        @report = report
        @printed_by = printed_by.presence || "-"
      end

      def generate
        builder = Exports::PdfReportBuilder.new(
          hotel: @hotel,
          title: "Agent Summary Statement",
          period_label: Exports::PdfTheme.format_date(@report.as_of_date),
          period_label_title: "As of",
          prepared_by: @printed_by,
          page_layout: :landscape
        )
        builder.add_header
        add_totals(builder)
        add_accounts(builder)
        builder.render
      end

      private

      def add_totals(builder)
        return if @report.totals.empty?

        builder.add_table(
          section_title: "Aging Totals",
          headers: aging_headers,
          rows: @report.totals.map { |currency, totals| aging_row(currency, totals) },
          numeric_columns: (1..6).to_a,
          total_row: nil,
          empty_message: "No aging totals are available."
        )
      end

      def add_accounts(builder)
        builder.add_table(
          section_title: "Agent & Airline Accounts",
          headers: [ "Account", *aging_headers ],
          rows: @report.rows.map { |row| account_row(row) },
          numeric_columns: (2..7).to_a,
          total_row: nil,
          empty_message: "No outstanding balances for agent or airline accounts.",
          density: :dense
        )
      end

      def aging_headers
        [ "Currency", "Current", "1-30", "31-60", "61-90", "90+", "Total" ]
      end

      def aging_row(currency, totals)
        [
          currency,
          money(totals.current),
          money(totals.days_1_30),
          money(totals.days_31_60),
          money(totals.days_61_90),
          money(totals.days_over_90),
          money(totals.total)
        ]
      end

      def account_row(row)
        [ row.corporate_account.name, *aging_row(row.currency, row.buckets), money(row.total_outstanding) ]
      end

      def money(value) = Exports::PdfTheme.money(value)
    end
  end
end
