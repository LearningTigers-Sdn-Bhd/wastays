# frozen_string_literal: true

module HotelPortal
  module Reports
    class CashierActivityExportTable
      def initialize(report:, visible_columns:)
        @report = report
        @columns = CashierActivityColumns.selected(visible_columns)
      end

      attr_reader :columns

      def headers = columns.flat_map(&:export_labels)
      def pdf_headers = columns.map(&:pdf_label)
      def excel_widths = columns.flat_map { |column| Array.new(column.export_labels.size, column.excel_width) }
      def pdf_widths = columns.map(&:pdf_width)
      def rows = transactions.map { |transaction| row_values(row_for(transaction), pdf: false) }
      def pdf_rows = transactions.map { |transaction| row_values(row_for(transaction), pdf: true) }

      def money_indexes
        headers.each_index.select { |index| headers[index] == "Amount" }
      end

      private

      attr_reader :report

      def row_for(transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: report.mode_by_transaction_id.fetch(transaction.id),
          section: report.section_by_transaction_id.fetch(transaction.id),
          origin: report.non_cash_origin_by_transaction_id[transaction.id],
          handling: report.handling_by_transaction_id&.[](transaction.id),
          received_by_key: report.received_by_key_by_transaction_id&.[](transaction.id)
        )
      end

      def transactions
        report.transactions || Array(report.cash_transactions) + Array(report.non_cash_transactions)
      end

      def row_values(row, pdf:)
        columns.flat_map do |column|
          case column.key
          when "date_time" then [ date_time(row, pdf:) ]
          when "date" then [ row.posting_date.strftime("%d %b %Y") ]
          when "time" then [ row.posted_at&.strftime("%H:%M") ]
          when "reservation"
            pdf ? [ [ "Booking #{row.booking_number}", "Confirmation #{row.confirmation_code}" ].join("\n") ] : [ row.booking_number, row.confirmation_code ]
          when "guest_details" then pdf ? [ [ row.guest_name, "Room #{row.room_number}" ].join("\n") ] : [ row.guest_name, row.room_number ]
          when "folio" then [ row.folio_number ]
          when "invoice" then [ row.invoice_number ]
          when "handling" then [ row.handling ]
          when "payment_mode" then [ row.settlement_mode ]
          when "stage" then [ row.section ]
          when "received_by" then [ row.received_by ]
          when "remarks" then [ row.description ]
          when "currency" then [ row.currency ]
          when "amount" then [ row.signed_amount ]
          end
        end
      end

      def date_time(row, pdf:)
        return row.posting_date.strftime("%d %b %Y") unless row.posted_at
        return "#{row.posting_date.strftime('%d %b %Y')}\n#{row.posted_at.strftime('%H:%M')}" if pdf

        "#{row.posting_date.iso8601}T#{row.posted_at.strftime('%H:%M:%S')}"
      end
    end
  end
end
