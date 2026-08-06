# frozen_string_literal: true

require "ostruct"

module Bookings
  class SetPrimaryGuest
    def self.call(booking:, booking_guest:, actor: nil)
      new(booking: booking, booking_guest: booking_guest, actor: actor).call
    end

    def initialize(booking:, booking_guest:, actor: nil)
      @booking = booking
      @booking_guest = booking_guest
      @actor = actor
    end

    def call
      return failure("Guest must belong to the selected booking.") unless @booking_guest.booking_id == @booking.id

      previous = nil
      BookingGuest.transaction do
        @booking.lock!
        previous = @booking.booking_guests.find_by(role: "primary")
        previous&.update!(role: "additional", is_primary: false) unless previous == @booking_guest
        @booking_guest.update!(role: "primary", is_primary: true)
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "update",
          category: "other",
          source: "booking_workspace",
          old_value: { primary_booking_guest_id: previous&.id },
          new_value: { primary_booking_guest_id: @booking_guest.id }
        )
      end

      OpenStruct.new(success?: true, booking_guest: @booking_guest)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, error: message, booking_guest: nil)
    end
  end
end
