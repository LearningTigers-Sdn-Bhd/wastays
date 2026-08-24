# frozen_string_literal: true

module HotelPortal
  module Reports
    class DepositLiabilityReport
      SCOPE_NOTE = "This report includes booking prepayments and security deposits. Security deposits remain liabilities until staff release or apply them."
      Result = Struct.new(:as_of_date, :rows, :totals, keyword_init: true)

      def initialize(hotel:, as_of_date:)
        @hotel = hotel
        @as_of_date = as_of_date.to_date
      end

      def call
        rows = folio_rows + unapplied_deposit_rows
        rows.sort_by! { |row| [ row[:sort_date], row[:confirmation_token].to_s, row[:folio_number].to_s ] }

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
                category: "booking_payment",
                posting_date: ..@as_of_date
              })
              .preload(:folio_transactions, booking: { booking_rooms: :room_type })
              .distinct
      end

      def row_for(folio)
        transactions = folio.folio_transactions.select { |transaction| transaction.posting_date <= @as_of_date }
        deposit_amount = sum_amount(transactions, transaction_type: "payment", category: "booking_payment")
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
          booking_payment_amount: deposit_amount.round(2),
          earned_amount: earned_amount.round(2),
          refund_amount: refund_amount.round(2),
          remaining_liability: remaining_liability.round(2),
          latest_deposit_posting_date: latest_deposit_posting_date(transactions),
          sort_date: booking.check_in
        }
      end

      def folio_rows
        folios.sort_by { |folio| [ folio.booking.check_in, folio.booking.created_at, folio.id ] }
          .filter_map { |folio| row_for(folio) }
      end

      def unapplied_deposit_rows
        deposits.filter_map do |deposit|
          movements = deposit.deposit_movements.select { |movement| movement.occurred_at.to_date <= @as_of_date }
          applied = movement_sum(movements, "apply") - movement_sum(movements, "reverse")
          returned = movement_sum(movements, "release") + movement_sum(movements, "refund")
          available = deposit.amount.to_d - applied - returned
          next unless available.positive?

          deposit_liability_row(deposit, available, returned)
        end
      end

      def deposits
        @hotel.deposits
          .where(received_at: ..@as_of_date.end_of_day)
          .includes(:deposit_movements, booking: { booking_rooms: :room_type }, group_booking: { bookings: { booking_rooms: :room_type } })
      end

      def movement_sum(movements, type)
        movements.select { |movement| movement.movement_type == type }.sum { |movement| movement.amount.to_d }
      end

      def deposit_liability_row(deposit, available, returned)
        owner = deposit.booking || deposit.group_booking
        booking = deposit.booking
        {
          booking_id: booking&.id,
          guest_name: booking&.guest_name || deposit.group_booking.name,
          confirmation_token: owner.confirmation_token,
          booking_status: owner.status.to_s.humanize,
          stay_dates: booking ? stay_dates(booking) : group_stay_dates(deposit.group_booking),
          room_details: booking ? room_details(booking) : group_room_details(deposit.group_booking),
          folio_number: "Unapplied #{deposit.kind.humanize}",
          booking_payment_amount: available.round(2),
          earned_amount: 0.to_d,
          refund_amount: returned.round(2),
          remaining_liability: available.round(2),
          latest_deposit_posting_date: deposit.received_at.to_date,
          sort_date: booking&.check_in || deposit.group_booking.default_check_in || deposit.received_at.to_date
        }
      end

      def group_stay_dates(group)
        return "—" if group.default_check_in.blank? || group.default_check_out.blank?

        "#{group.default_check_in.strftime('%d %b %Y')} - #{group.default_check_out.strftime('%d %b %Y')}"
      end

      def group_room_details(group)
        count = group.bookings.sum { |booking| booking.booking_rooms.size }
        "#{count} room#{'s' unless count == 1}"
      end

      def sum_amount(transactions, transaction_type:, category:)
        transactions.select do |transaction|
          transaction.transaction_type == transaction_type && transaction.category == category
        end.sum { |transaction| transaction.amount.to_d }
      end

      def latest_deposit_posting_date(transactions)
        transactions.select { |transaction| transaction.payment? && transaction.category == "booking_payment" }
                    .map(&:posting_date)
                    .max
      end

      def stay_dates(booking)
        "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}"
      end

      def room_details(booking)
        details = booking.booking_rooms.group_by do |room|
          snapshot_name = room.room_type_snapshot.is_a?(Hash) ? room.room_type_snapshot["name"].presence : nil
          snapshot_name || room.room_type&.name || "Room"
        end.map do |room_name, rooms|
          "#{rooms.size}x #{room_name}"
        end

        details.presence&.join(", ") || "No rooms assigned"
      end

      def totals_for(rows)
        {
          booking_count: rows.size,
          booking_payment_amount: rows.sum { |row| row[:booking_payment_amount].to_d },
          earned_amount: rows.sum { |row| row[:earned_amount].to_d },
          refund_amount: rows.sum { |row| row[:refund_amount].to_d },
          remaining_liability: rows.sum { |row| row[:remaining_liability].to_d }
        }
      end
    end
  end
end
