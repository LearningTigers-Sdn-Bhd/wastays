# frozen_string_literal: true

module HotelPortal
  module Reports
    class DepositLiabilityReport
      Result = Struct.new(:as_of_date, :rows, :totals, keyword_init: true)

      def initialize(hotel:, as_of_date:)
        @hotel = hotel
        @as_of_date = as_of_date.to_date
      end

      def call
        rows = folios.sort_by { |folio| [ folio.booking.check_in, folio.booking.created_at, folio.id ] }
                     .filter_map { |folio| row_for(folio) }

        Result.new(
          as_of_date: @as_of_date,
          rows: rows,
          totals: totals_for(rows)
        )
      end

      private

      def folios
        BookingFolio.joins(:booking, :folio_transactions)
              .where(bookings: { hotel_id: @hotel.id })
              .where(folio_transactions: {
                transaction_type: "payment",
                category: "advance_deposit",
                posting_date: ..@as_of_date
              })
              .preload(:folio_transactions, booking: { booking_rooms: :room_type })
              .distinct
      end

      def row_for(folio)
        transactions = folio.folio_transactions.select { |transaction| transaction.posting_date <= @as_of_date }
        deposit_amount = sum_amount(transactions, transaction_type: "payment", category: "advance_deposit")
        return if deposit_amount <= 0

        earned_amount = transactions.select { |transaction| transaction.charge? || transaction.adjustment? }.sum { |transaction| transaction.amount.to_d }
        refund_amount = sum_amount(transactions, transaction_type: "payment", category: "refund").abs
        remaining_liability = deposit_amount - earned_amount - refund_amount
        return unless remaining_liability.positive?

        booking = folio.booking
        {
          booking_id: booking.id,
          guest_name: booking.guest_name,
          confirmation_token: booking.confirmation_token,
          booking_status: booking.status.to_s.humanize,
          stay_dates: stay_dates(booking),
          room_details: room_details(booking),
          folio_number: folio.folio_number,
          advance_deposit_amount: deposit_amount.round(2),
          earned_amount: earned_amount.round(2),
          refund_amount: refund_amount.round(2),
          remaining_liability: remaining_liability.round(2),
          latest_deposit_posting_date: latest_deposit_posting_date(transactions)
        }
      end

      def sum_amount(transactions, transaction_type:, category:)
        transactions.select do |transaction|
          transaction.transaction_type == transaction_type && transaction.category == category
        end.sum { |transaction| transaction.amount.to_d }
      end

      def latest_deposit_posting_date(transactions)
        transactions.select { |transaction| transaction.payment? && transaction.category == "advance_deposit" }
                    .map(&:posting_date)
                    .max
      end

      def stay_dates(booking)
        "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}"
      end

      def room_details(booking)
        details = booking.booking_rooms.map do |room|
          snapshot_name = room.room_type_snapshot.is_a?(Hash) ? room.room_type_snapshot["name"].presence : nil
          room_name = snapshot_name || room.room_type&.name || "Room"
          "#{room.quantity}x #{room_name}"
        end

        details.presence&.join(", ") || "No rooms assigned"
      end

      def totals_for(rows)
        {
          booking_count: rows.size,
          advance_deposit_amount: rows.sum { |row| row[:advance_deposit_amount].to_d },
          earned_amount: rows.sum { |row| row[:earned_amount].to_d },
          refund_amount: rows.sum { |row| row[:refund_amount].to_d },
          remaining_liability: rows.sum { |row| row[:remaining_liability].to_d }
        }
      end
    end
  end
end
