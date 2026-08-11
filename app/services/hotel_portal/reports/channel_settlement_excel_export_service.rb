# frozen_string_literal: true

module HotelPortal
  module Reports
    class ChannelSettlementExcelExportService
      HEADERS = [ "Provider", "Expected Net", "Received", "Outstanding", "Variance" ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "OTA Settlement Report", period_label: period_label).generate do |builder|
          if @report.currency_totals.any?
            @report.currency_totals.each { |total| add_currency_sheet(builder, total) }
          else
            add_empty_sheet(builder)
          end
        end
      end

      private

      def add_currency_sheet(builder, total)
        currency = total.fetch(:currency)
        rows = @report.rows.select { |row| row[:currency] == currency }
        sheet = builder.add_sheet(name: "#{currency} Settlements", widths: [ 24, 18, 18, 18, 18 ])
        builder.add_header(sheet: sheet, subtitle: currency)
        builder.add_summary(sheet: sheet, metrics: summary_metrics(total, currency))
        builder.add_table(
          sheet: sheet,
          section_title: "Provider reconciliation",
          headers: HEADERS,
          rows: rows.map { |row| [ row[:provider].to_s.titleize, row[:expected_net_amount], row[:received_amount], row[:outstanding_amount], row[:variance_amount] ] },
          column_types: %i[text money money money money],
          total_row: [ "TOTAL", total[:expected_net_amount], total[:received_amount], total[:outstanding_amount], total[:variance_amount] ],
          empty_message: "No OTA settlements for this currency in the selected period."
        )
      end

      def add_empty_sheet(builder)
        sheet = builder.add_sheet(name: "OTA Settlements", widths: [ 24, 18, 18, 18, 18 ])
        builder.add_header(sheet: sheet)
        builder.add_table(
          sheet: sheet,
          section_title: "Provider reconciliation",
          headers: HEADERS,
          rows: [],
          column_types: %i[text money money money money],
          total_row: nil,
          empty_message: "No OTA settlements for the selected period."
        )
      end

      def summary_metrics(total, currency)
        [
          [ "Expected Net", total[:expected_net_amount], currency ],
          [ "Received", total[:received_amount], currency ],
          [ "Outstanding", total[:outstanding_amount], currency ],
          [ "Variance", total[:variance_amount], currency ]
        ]
      end

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end
    end
  end
end
