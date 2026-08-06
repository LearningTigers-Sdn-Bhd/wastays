# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class DailyReportCsvExportService
      BOM = "\xEF\xBB\xBF"

      def initialize(tab:, revenue_report:, cashier_report:, charge_register: [])
        @tab = tab
        @revenue_report = revenue_report
        @cashier_report = cashier_report
        @charge_register = charge_register
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
        append_metrics(csv, "Cashier Sales (Cash Flow)", [
          [ "Cash Movements", cashier[:movement_count], nil ],
          [ "Total Collected", decimal(cashier[:total_collected]), "MYR" ],
          [ "Total Refunded", decimal(cashier[:total_refunded]), "MYR" ],
          [ "Net Cash", decimal(cashier[:net_cash]), "MYR" ]
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
        append_cashier_transactions(csv, "Advance", @cashier_report.advance_scope)
        append_cashier_transactions(csv, "Settlement", @cashier_report.settlement_scope)

        csv << [ "Cashier Summary" ]
        csv << [ "Mode", "Currency", "Description", "Amount (IN)", "Amount (OUT)", "Balance" ]
        @cashier_report.mode_summary_rows.each do |row|
          csv << [ row[:mode], row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        @cashier_report.mode_totals.each do |row|
          csv << [ "#{row[:mode]} Total", nil, nil, decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        csv << []

        csv << [ "Currency Summary" ]
        csv << [ "Currency", "Description", "Amount (IN)", "Amount (OUT)", "Balance" ]
        @cashier_report.currency_summary_rows.each do |row|
          csv << [ row[:currency], row[:section], decimal(row[:amount_in]), decimal(row[:amount_out]), decimal(row[:balance]) ]
        end
        grand = @cashier_report.grand_total
        csv << [ "Grand Total", nil, decimal(grand[:amount_in]), decimal(grand[:amount_out]), decimal(grand[:balance]) ]
      end

      def append_transactions(csv, title, transactions)
        csv << [ title ]
        transaction_csv = DailyRevenueTransactionsCsvExportService.new(rows: transactions).generate.delete_prefix(BOM)
        CSV.parse(transaction_csv).each { |row| csv << row }
        csv << []
      end

      def append_cashier_transactions(csv, title, transactions)
        csv << [ title ]
        csv << HotelPortal::Reports::DailyReportExcelExportService::CASHIER_HEADERS
        transactions.each do |transaction|
          row = cashier_row(transaction)
          csv << [
            cashier_date_time(row),
            row.booking_reference, row.guest_name, row.room_number, row.folio_number, row.invoice_number,
            row.settlement_mode, row.received_by, row.description, row.currency, decimal(row.signed_amount)
          ]
        end
        csv << []
      end

      def cashier_row(transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: @cashier_report.mode_by_transaction_id[transaction.id]
        )
      end

      def cashier_date_time(row)
        return row.posting_date.iso8601 unless row.posted_at

        "#{row.posting_date.iso8601}T#{row.posted_at.strftime('%H:%M:%S')}"
      end

      def decimal(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
