# frozen_string_literal: true

module HotelPortal
  module Reports
    class SstReport
      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, date_preset: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @date_preset = date_preset.to_s
      end

      def call
        rows = load_bookings.map { |booking| row_for(booking) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          totals: {
            booking_count: rows.size,
            taxable_amount: rows.sum { |r| r[:taxable_amount] },
            sst_amount: rows.sum { |r| r[:sst_amount] },
            total_amount: rows.sum { |r| r[:total_amount] }
          }
        )
      end

      private

      def load_bookings
        @hotel.bookings
              .joins(booking_folio: :folio_transactions)
              .where(
                folio_transactions: {
                  transaction_type: "charge",
                  category: "tax",
                  voided_by_transaction_id: nil
                }
              )
              .where(
                "folio_transactions.description ILIKE ? OR folio_transactions.description ILIKE ?",
                "%SST%", "%service tax%"
              )
              .where(folio_transactions: { posting_date: @start_date..@end_date })
              .distinct
              .includes(booking_folio: :folio_transactions)
              .order(:check_in, :id)
      end

      def row_for(booking)
        txns = booking.booking_folio.folio_transactions.select do |t|
          t.posting_date.between?(@start_date, @end_date) && t.voided_by_transaction_id.nil?
        end

        sst_txns = txns.select { |t| t.transaction_type == "charge" && t.category == "tax" && sst_description?(t.description) }
        accommodation_txns = txns.select { |t| t.transaction_type == "charge" && t.category == "accommodation" }

        sst_amount = sst_txns.sum { |t| t.amount.to_d }
        taxable_amount = accommodation_txns.sum { |t| t.amount.to_d }
        taxable_amount = (sst_amount / 0.08).round(2) if taxable_amount.zero? && sst_amount > 0

        {
          booking_id: booking.id,
          invoice_number: booking.invoice_number.presence || booking.confirmation_token,
          guest_name: booking.guest_name,
          report_month: booking.check_in.to_date.beginning_of_month,
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          taxable_amount: taxable_amount,
          sst_amount: sst_amount,
          total_amount: taxable_amount + sst_amount
        }
      end

      def sst_description?(description)
        return false if description.blank?
        desc = description.downcase
        desc.include?("sst") || desc.include?("service tax")
      end
    end
  end
end
