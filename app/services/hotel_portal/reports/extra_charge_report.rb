# frozen_string_literal: true

module HotelPortal
  module Reports
    class ExtraChargeReport
      TABS = %w[fb non_fb].freeze

      Result = Struct.new(:start_date, :end_date, :rows, :totals, :active_tab, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, tab:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @active_tab = TABS.include?(tab.to_s) ? tab.to_s : "fb"
      end

      def call
        rows = load_transactions.map { |transaction| row_for(transaction) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          active_tab: @active_tab,
          totals: {
            transaction_count: rows.size,
            total_amount: rows.sum { |row| row[:amount] }
          }
        )
      end

      private

      def load_transactions
        scope = FolioTransaction.joins(booking_folio: :booking)
                                .where(bookings: { hotel_id: @hotel.id })
                                .where(transaction_type: "charge", posting_date: @start_date..@end_date, voided_by_transaction_id: nil)

        scope = if @active_tab == "fb"
          scope.where(category: "fb")
        else
          scope.where.not(category: %w[fb accommodation tax])
        end

        scope.includes(booking_folio: :booking)
             .order(:posting_date, :created_at, :id)
      end

      def row_for(transaction)
        booking = transaction.booking_folio.booking

        {
          posting_date: transaction.posting_date.to_date,
          booking_id: booking.id,
          booking_reference: booking.invoice_number.presence || booking.confirmation_token,
          folio_number: transaction.booking_folio.folio_reference_display,
          guest_name: booking.guest_name,
          description: transaction.description,
          category: transaction.category,
          amount: transaction.amount.to_d
        }
      end
    end
  end
end
