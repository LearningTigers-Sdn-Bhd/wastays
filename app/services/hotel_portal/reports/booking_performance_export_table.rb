# frozen_string_literal: true

module HotelPortal
  module Reports
    # The export table of the booking performance report.
    module BookingPerformanceExportTable
      module_function

      def new(rows:, visible_columns:)
        ColumnExportTable.new(
          records: rows,
          columns: BookingPerformanceColumns,
          visible_columns:,
          values: method(:cell_values)
        )
      end

      def cell_values(row, key, pdf)
        case key
        when "booked_on" then pdf ? date(row.booked_on) : row.booked_on
        when "booking"
          pdf ? "#{row.booking_number}\nCode: #{row.confirmation_code}" : [ row.booking_number, row.confirmation_code ]
        when "confirmation_code" then row.confirmation_code
        when "guest" then row.guest_name
        when "stay"
          pdf ? "#{date(row.check_in)}\n#{date(row.check_out)}" : [ row.check_in, row.check_out ]
        when "check_in" then pdf ? date(row.check_in) : row.check_in
        when "check_out" then pdf ? date(row.check_out) : row.check_out
        when "source" then row.source_label
        when "fund_collector" then row.fund_collector_label
        when "status" then row.status_label
        when "payment_status" then row.payment_status_label
        when "gross" then row.gross
        when "taxes" then row.taxes
        when "commission" then row.commission
        when "net" then row.net
        when "currency" then row.currency
        end
      end

      def date(value) = value&.strftime("%d %b %Y") || "—"
    end
  end
end
