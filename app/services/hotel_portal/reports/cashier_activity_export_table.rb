# frozen_string_literal: true

module HotelPortal
  module Reports
    # The export table of the cashier activity report.
    module CashierActivityExportTable
      module_function

      def new(report:, visible_columns:)
        rows = transactions(report).map { |transaction| row_for(report, transaction) }
        ColumnExportTable.new(
          records: rows,
          columns: CashierActivityColumns,
          visible_columns:,
          values: method(:cell_values)
        )
      end

      def transactions(report)
        report.transactions || Array(report.cash_transactions) + Array(report.non_cash_transactions)
      end

      def row_for(report, transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: report.mode_by_transaction_id.fetch(transaction.id),
          section: report.section_by_transaction_id.fetch(transaction.id),
          origin: report.non_cash_origin_by_transaction_id[transaction.id],
          handling: report.handling_by_transaction_id&.[](transaction.id),
          received_by_key: report.received_by_key_by_transaction_id&.[](transaction.id)
        )
      end

      def cell_values(row, key, pdf)
        case key
        when "date_time" then date_time(row, pdf)
        when "date" then row.posting_date.strftime("%d %b %Y")
        when "time" then row.posted_at&.strftime("%H:%M")
        when "reservation"
          if pdf
            [ "Booking #{row.booking_number}", "Confirmation #{row.confirmation_code}" ].join("\n")
          else
            [ row.booking_number, row.confirmation_code ]
          end
        when "booking_number" then row.booking_number
        when "confirmation_code" then row.confirmation_code
        when "guest_details"
          pdf ? [ row.guest_name, "Room #{row.room_number}" ].join("\n") : [ row.guest_name, row.room_number ]
        when "folio" then row.folio_number
        when "invoice" then row.invoice_number
        when "handling" then row.handling
        when "payment_mode" then row.settlement_mode
        when "stage" then row.section
        when "received_by" then row.received_by
        when "remarks" then row.description
        when "currency" then row.currency
        when "amount" then row.signed_amount
        end
      end

      def date_time(row, pdf)
        return row.posting_date.strftime("%d %b %Y") unless row.posted_at
        return "#{row.posting_date.strftime('%d %b %Y')}\n#{row.posted_at.strftime('%H:%M')}" if pdf

        "#{row.posting_date.iso8601}T#{row.posted_at.strftime('%H:%M:%S')}"
      end
    end
  end
end
