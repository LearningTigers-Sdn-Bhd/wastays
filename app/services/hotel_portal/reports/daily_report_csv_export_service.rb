# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyReportCsvExportService
      BOM = "\xEF\xBB\xBF"

      def initialize(tab:, revenue_report:, cashier_report:, charge_register: [], cashier_view: "full",
                     visible_columns: CashierActivityColumns::DEFAULT_KEYS)
        @tab = tab
        @revenue_report = revenue_report
        @cashier_report = cashier_report
        @charge_register = charge_register
        @cashier_view = cashier_view.to_s.presence_in(%w[full activity summary]) || "full"
        @visible_columns = visible_columns
      end

      def generate
        BOM + CSV.generate do |csv|
          case @tab
          when "revenue" then append_revenue(csv)
          when "cashier" then append_cashier(csv)
          else append_overview(csv)
          end
        end
      end

      private

      def append_overview(csv)
        revenue = @revenue_report.totals
        cashier = @cashier_report.totals

        csv << [ "Section", "Metric", "Value", "Currency" ]
        append_metrics(csv, "Revenue (Accrual)", [
          [ "Bookings Engaged", revenue[:booking_count], nil ],
          [ "Total Charges", decimal(revenue[:total_charges]), "MYR" ],
          [ "Adjustments", decimal(revenue[:adjustments]), "MYR" ],
          [ "Net Revenue", decimal(revenue[:net_revenue]), "MYR" ]
        ])
        append_metrics(csv, "Cashier Activity (Cash Flow)", [
          [ "Movements", cashier[:movement_count], nil ],
          [ "Total Collected", decimal(cashier[:total_collected]), "MYR" ],
          [ "Total Refunded", decimal(cashier[:total_refunded]), "MYR" ],
          [ "Net At Desk", decimal(cashier[:net_cash]), "MYR" ]
        ])
      end

      def append_metrics(csv, title, rows)
        rows.each { |metric, value, currency| csv << [ title, metric, value, currency ] }
      end

      def append_revenue(csv)
        csv << [ "Daily Breakdown" ]
        csv << [ "Date", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Adjustments", "Net Revenue" ]
        @revenue_report.rows.each do |row|
          csv << [
            row[:date].iso8601, row[:booking_count], decimal(row[:accommodation]), decimal(row[:other_charges]),
            decimal(row[:tax]), decimal(row[:total_charges]), decimal(row[:adjustments]), decimal(row[:net_revenue])
          ]
        end
        csv << [ "Total", @revenue_report.totals[:booking_count], decimal(@revenue_report.totals[:accommodation]),
          decimal(@revenue_report.totals[:other_charges]), decimal(@revenue_report.totals[:tax]),
          decimal(@revenue_report.totals[:total_charges]), decimal(@revenue_report.totals[:adjustments]),
          decimal(@revenue_report.totals[:net_revenue]) ]
        csv << []

        csv << [ "Revenue by Source" ]
        csv << [ "Source", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Adjustments", "Net Revenue" ]
        @revenue_report.source_rows.each do |row|
          csv << [
            row[:source], row[:booking_count], decimal(row[:accommodation]), decimal(row[:other_charges]),
            decimal(row[:tax]), decimal(row[:total_charges]), decimal(row[:adjustments]), decimal(row[:net_revenue])
          ]
        end
        csv << [ "Total", @revenue_report.totals[:booking_count], decimal(@revenue_report.totals[:accommodation]),
          decimal(@revenue_report.totals[:other_charges]), decimal(@revenue_report.totals[:tax]),
          decimal(@revenue_report.totals[:total_charges]), decimal(@revenue_report.totals[:adjustments]),
          decimal(@revenue_report.totals[:net_revenue]) ]
        csv << []
        append_transactions(csv, "Revenue Register", @charge_register)
      end

      def append_cashier(csv)
        append_cashier_metrics(csv) if %w[full summary].include?(@cashier_view)
        append_cashier_transactions(csv) if %w[full activity].include?(@cashier_view)
        append_cashier_summaries(csv) if %w[full summary].include?(@cashier_view)
      end

      def append_cashier_metrics(csv)
        append_cashier_metric_group(csv, "At Desk", @cashier_report.at_desk_totals || @cashier_report.totals)
        append_cashier_metric_group(csv, "Not Handled At The Desk", @cashier_report.non_desk_totals || @cashier_report.non_cash_totals)
        csv << []
      end

      def append_cashier_metric_group(csv, title, totals)
        csv << [ title, "Movements", totals[:movement_count] ]
        csv << [ title, "Amount In", decimal(totals[:total_collected]), "MYR" ]
        csv << [ title, "Amount Out", decimal(totals[:total_refunded]), "MYR" ]
        csv << [ title, "Net", decimal(totals[:net_cash]), "MYR" ]
      end

      def append_cashier_summaries(csv)
        csv << [ "Activity By Payment Mode" ]
        csv << [ "Handling", "Mode", "Currency", "Stage", "Amount (IN)", "Amount (OUT)", "Balance" ]
        cashier_all_mode_summary_rows.each do |row|
          csv << [ row[:handling_label], row[:mode], row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        cashier_handling_totals.each do |row|
          csv << [ "#{row[:handling_label]} Subtotal", nil, nil, nil, decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        grand = cashier_grand_total
        csv << [ "Grand Total", nil, nil, nil, decimal(grand[:amount_in]), decimal(grand[:amount_out]), decimal(grand[:balance]) ]
        csv << []

        csv << [ "Currency Summary" ]
        csv << [ "Handling", "Currency", "Stage", "Amount (IN)", "Amount (OUT)", "Balance" ]
        cashier_all_currency_summary_rows.each do |row|
          csv << [ row[:handling_label], row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        cashier_handling_totals.each do |row|
          csv << [ "#{row[:handling_label]} Subtotal", nil, nil, decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        grand = cashier_grand_total
        csv << [ "Grand Total", nil, nil, decimal(grand[:amount_in]), decimal(grand[:amount_out]), decimal(grand[:balance]) ]
      end

      def append_transactions(csv, title, transactions)
        csv << [ title ]
        transaction_csv = DailyRevenueTransactionsCsvExportService.new(rows: transactions).generate.delete_prefix(BOM)
        CSV.parse(transaction_csv).each { |row| csv << row }
        csv << []
      end

      def append_cashier_transactions(csv)
        table = CashierActivityExportTable.new(report: @cashier_report, visible_columns: @visible_columns)
        csv << [ "Payment Activity" ]
        csv << table.headers
        table.rows.each { |row| csv << row.map { |value| value.is_a?(BigDecimal) ? decimal(value) : value } }
        csv << []
      end

      def cashier_row(transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id],
          section: @cashier_report.section_by_transaction_id[transaction.id],
          origin: @cashier_report.non_cash_origin_by_transaction_id&.[](transaction.id)
        )
      end

      def cashier_date_time(row)
        return row.posting_date.iso8601 unless row.posted_at

        "#{row.posting_date.iso8601}T#{row.posted_at.strftime('%H:%M:%S')}"
      end

      def decimal(value)
        format("%.2f", value.to_d)
      end

      def cashier_all_mode_summary_rows = @cashier_report.all_mode_summary_rows || @cashier_report.mode_summary_rows
      def cashier_all_currency_summary_rows = @cashier_report.all_currency_summary_rows || @cashier_report.currency_summary_rows
      def cashier_handling_totals = @cashier_report.respond_to?(:handling_totals) ? Array(@cashier_report.handling_totals) : []
      def cashier_grand_total = @cashier_report.all_grand_total || @cashier_report.grand_total
    end
  end
end
