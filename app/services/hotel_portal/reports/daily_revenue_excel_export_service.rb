# frozen_string_literal: true

require "cgi"

module HotelPortal
  module Reports
    class DailyRevenueExcelExportService
      XML_HEADER = %(<?xml version="1.0"?>).freeze

      def initialize(report:, transactions: [])
        @report = report
        @transactions = transactions
      end

      def generate
        <<~XML
          #{XML_HEADER}
          <?mso-application progid="Excel.Sheet"?>
          <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
            xmlns:o="urn:schemas-microsoft-com:office:office"
            xmlns:x="urn:schemas-microsoft-com:office:excel"
            xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
            <Worksheet ss:Name="Summary">
              <Table>
                #{summary_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="Daily Revenue">
              <Table>
                #{daily_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="Revenue by Source">
              <Table>
                #{source_rows}
              </Table>
            </Worksheet>
            <Worksheet ss:Name="All Transactions">
              <Table>
                #{transaction_rows}
              </Table>
            </Worksheet>
          </Workbook>
        XML
      end

      private

      def summary_rows
        rows = []
        rows << spreadsheet_row([ "Metric", "Value" ])
        rows << spreadsheet_row([ "Total Bookings", @report.totals[:booking_count] ])
        rows << spreadsheet_row([ "Accommodation", money(@report.totals[:accommodation]) ])
        rows << spreadsheet_row([ "Other Charges", money(@report.totals[:other_charges]) ])
        rows << spreadsheet_row([ "Tax", money(@report.totals[:tax]) ])
        rows << spreadsheet_row([ "Total Charges", money(@report.totals[:total_charges]) ])
        rows << spreadsheet_row([ "Discount", money(@report.totals[:discount]) ])
        rows << spreadsheet_row([ "Online Payment", money(@report.totals[:gateway_payment]) ])
        rows << spreadsheet_row([ "Cash Payment", money(@report.totals[:cash_payment]) ])
        rows << spreadsheet_row([ "Deposit", money(@report.totals[:booking_payment]) ])
        rows << spreadsheet_row([ "Refund", money(@report.totals[:refund]) ])
        rows << spreadsheet_row([ "Net Amount", money(@report.totals[:net_amount]) ])
        rows.join("\n")
      end

      def daily_rows
        rows = []
        rows << spreadsheet_row([ "Date", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Discount", "Online", "Cash", "Deposit", "Refund", "Net" ])
        @report.rows.each do |row|
          rows << spreadsheet_row([
            row[:date].strftime("%Y-%m-%d"),
            row[:booking_count],
            money(row[:accommodation]),
            money(row[:other_charges]),
            money(row[:tax]),
            money(row[:total_charges]),
            money(row[:discount]),
            money(row[:gateway_payment]),
            money(row[:cash_payment]),
            money(row[:booking_payment]),
            money(row[:refund]),
            money(row[:net_amount])
          ])
        end
        rows.join("\n")
      end

      def source_rows
        rows = []
        rows << spreadsheet_row([ "Source", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Net" ])
        @report.source_rows.each do |row|
          rows << spreadsheet_row([
            row[:source],
            row[:booking_count],
            money(row[:accommodation]),
            money(row[:other_charges]),
            money(row[:tax]),
            money(row[:total_charges]),
            money(row[:net_amount])
          ])
        end
        rows.join("\n")
      end

      def transaction_rows
        rows = []
        rows << spreadsheet_row(HotelPortal::Reports::DailyRevenueTransactionsCsvExportService::HEADERS)
        @transactions.each do |transaction|
          row = HotelPortal::Reports::DailyRevenueTransactionRow.new(transaction)
          rows << spreadsheet_row([
            row.posting_date.iso8601,
            row.posted_at&.iso8601,
            row.transaction_code,
            row.service_name,
            row.transaction_type,
            row.category,
            row.description,
            row.booking_reference,
            row.folio_number,
            row.guest_name,
            row.room_number,
            row.payment_method,
            row.posting_source,
            row.actor_name,
            row.stay_date,
            row.relationship_status,
            row.related_transaction_id,
            money(row.signed_amount),
            row.currency
          ])
        end
        rows.join("\n")
      end

      def spreadsheet_row(values)
        cells = values.map do |value|
          escaped = CGI.escapeHTML(value.to_s)
          %(<Cell><Data ss:Type="String">#{escaped}</Data></Cell>)
        end.join

        %(<Row>#{cells}</Row>)
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
