# frozen_string_literal: true

require "ostruct"

module GroupBookings
  class RemoveBooking
    def self.call(group_booking:, booking:, actor:, reason:)
      new(group_booking: group_booking, booking: booking, actor: actor, reason: reason).call
    end

    def initialize(group_booking:, booking:, actor:, reason:)
      @group_booking = group_booking
      @booking = booking
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      return failure("Reason can't be blank.") if @reason.blank?
      return failure("Booking does not belong to this group.") unless @booking.group_booking_id == @group_booking.id

      @booking.with_lock do
        old_value = { group_booking_id: @group_booking.id, group_position: @booking.group_position }
        @booking.update!(group_booking: nil, group_position: nil)
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "update",
          category: "other",
          source: "group_booking",
          old_value: old_value,
          new_value: { group_booking_id: nil, group_position: nil },
          reason: @reason
        )
      end

      OpenStruct.new(success?: true, booking: @booking)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, error: message, booking: @booking)
    end
  end
end
