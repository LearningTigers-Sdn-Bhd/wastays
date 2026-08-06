# frozen_string_literal: true

module HotelPortal
  module Reports
    class TaxComplianceExportTable
      attr_reader :title, :section_title, :headers, :rows, :column_types, :total_row, :summary_metrics, :empty_message

      def initialize(report:, type:)
        @report = report
        send("build_#{type}")
      end

      private

      def build_tourism_tax
        @title = "Tourism Tax Report"
        @section_title = "Tourism Tax Records"
        @headers = [ "Guest Name", "Nationality", "Booking Ref", "Check In", "Check Out", "Nights", "Tax Due (MYR)", "Tax Collected (MYR)", "Collection Status" ]
        @column_types = %i[text text text date date integer money money text]
        @rows = @report.rows.map { |row| row.values_at(:guest_name, :guest_country, :booking_reference, :check_in, :check_out, :nights, :tax_due, :tax_collected, :collection_status) }
        @total_row = [ "TOTAL", nil, nil, nil, nil, @report.totals[:guest_count], @report.totals[:total_due], @report.totals[:total_collected], nil ]
        @summary_metrics = [ [ "Guests", @report.totals[:guest_count], nil ], [ "Total Due", @report.totals[:total_due], :currency ], [ "Total Collected", @report.totals[:total_collected], :currency ] ]
        @empty_message = "No tourism tax bookings found for this period."
      end

      def build_sst
        @title = "SST Financial Report"
        @section_title = "SST Transactions"
        @headers = [ "Invoice / Ref", "Guest Name", "Check-In", "Check-Out", "Taxable Amount (MYR)", "SST 8% (MYR)", "Total (MYR)" ]
        @column_types = %i[text text date date money money money]
        @rows = @report.rows.map { |row| row.values_at(:invoice_number, :guest_name, :check_in, :check_out, :taxable_amount, :sst_amount, :total_amount) }
        @total_row = [ "TOTAL", nil, nil, nil, @report.totals[:taxable_amount], @report.totals[:sst_amount], @report.totals[:total_amount] ]
        @summary_metrics = [ [ "Bookings", @report.totals[:booking_count], nil ], [ "Taxable Amount", @report.totals[:taxable_amount], :currency ], [ "SST Collected", @report.totals[:sst_amount], :currency ], [ "Grand Total", @report.totals[:total_amount], :currency ] ]
        @empty_message = "No SST transactions found for this period."
      end

      def build_non_national
        totals = @report.respond_to?(:totals) ? @report.totals : { guest_count: @report.rows.size, nights: 0 }
        @title = "Non-National Report"
        @section_title = "Non-National Guests"
        @headers = [ "Full Name", "Nationality", "Date of Birth", "Home Address", "Check In Date", "Check In Time", "Check Out Date" ]
        @column_types = %i[text text date text date text date]
        @rows = @report.rows.map { |row| [ row[:guest_name], row[:guest_country], row[:date_of_birth], row[:guest_home_address], row[:check_in], row[:checked_in_at]&.strftime("%I:%M %p"), row[:check_out] ] }
        @total_row = [ "TOTAL", nil, nil, nil, nil, nil, nil ]
        @summary_metrics = [ [ "Guests", totals[:guest_count], nil ], [ "Nights", totals[:nights], nil ] ]
        @empty_message = "No in-house non-national guests found for this period."
      end
    end
  end
end
