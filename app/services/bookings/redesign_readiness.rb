# frozen_string_literal: true

module Bookings
  class RedesignReadiness
    def self.call
      new.call
    end

    def call
      multi_room = Booking.joins(:booking_rooms).group("bookings.id").having("COUNT(booking_rooms.id) > 1")
      ungrouped_multi_room = multi_room.where(group_booking_id: nil)
      finance_blocked_ids = finance_blocked_scope.where(id: ungrouped_multi_room.select(:id)).select(:id)
      external_blocked_ids = external_blocked_scope.where(id: ungrouped_multi_room.select(:id)).select(:id)

      {
        bookings_with_multiple_room_rows: multi_room.count.size,
        ungrouped_multi_room_bookings: ungrouped_multi_room.count.size,
        already_grouped_multi_room_bookings: multi_room.where.not(group_booking_id: nil).count.size,
        multi_room_finance_blockers: Booking.where(id: finance_blocked_ids).count,
        multi_room_external_blockers: Booking.where(id: external_blocked_ids).count,
        multi_room_ready_to_split: ungrouped_multi_room.count.size,
        multi_room_requiring_anchor_review: ungrouped_multi_room.where(
          id: Booking.where(id: finance_blocked_ids).or(Booking.where(id: external_blocked_ids)).select(:id)
        ).count.size,
        duplicate_primary_guests: duplicate_primary_scope.count.size,
        missing_primary_guests: missing_primary_scope.count,
        duplicate_booking_guests: duplicate_guest_scope.count.size,
        bookings_without_rooms: roomless_scope.count,
        pending_bookings_without_rooms: roomless_scope.where(status: "pending").count,
        non_pending_bookings_without_rooms: roomless_scope.where.not(status: "pending").count
      }
    end

    private

    def duplicate_primary_scope
      BookingGuest.where(is_primary: true).group(:booking_id).having("COUNT(*) > 1")
    end

    def missing_primary_scope
      Booking.where.not(status: "pending")
        .where.not(id: BookingGuest.where(is_primary: true).select(:booking_id))
    end

    def duplicate_guest_scope
      BookingGuest.group(:booking_id, :guest_id).having("COUNT(*) > 1")
    end

    def roomless_scope
      Booking.left_joins(:booking_rooms).where(booking_rooms: { id: nil })
    end

    def finance_blocked_scope
      folio_transaction_booking_ids = BookingFolio.joins(:folio_transactions).select(:booking_id)
      Booking.where.not(payout_batch_id: nil)
        .or(Booking.where(id: Deposit.select(:booking_id)))
        .or(Booking.where(id: PaymentTransaction.where.not(booking_id: nil).select(:booking_id)))
        .or(Booking.where(id: RefundRequest.select(:booking_id)))
        .or(Booking.where(id: folio_transaction_booking_ids))
    end

    def external_blocked_scope
      Booking.where.not(external_reference: [ nil, "" ])
        .or(Booking.where.not(channel_manager_reference: [ nil, "" ]))
        .or(Booking.where.not(source: [ nil, "", "internal", "walk_in" ]))
    end
  end
end
