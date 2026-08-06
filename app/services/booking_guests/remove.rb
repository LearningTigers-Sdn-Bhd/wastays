# frozen_string_literal: true

require "ostruct"

module BookingGuests
  class Remove
    def self.call(booking_guest:, actor:) = new(booking_guest:, actor:).call

    def initialize(booking_guest:, actor:)
      @booking_guest = booking_guest
      @booking = booking_guest.booking
      @guest = booking_guest.guest
      @actor = actor
    end

    def call
      return failure("The primary guest cannot be removed. Select another primary guest first.") if @booking_guest.primary?
      party = @booking_guest.booking_billing_party
      if party&.booking_folios&.exists?
        return failure("This guest owns folios or financial history. Reassign the folio ownership before removing the guest.")
      end

      Booking.transaction do
        party&.destroy!
        @booking_guest.reload.destroy!
        @guest.destroy! if @guest.booking_guests.empty?
        Bookings::RecordAuditLog.call!(auditable: @booking, user: @actor, action_type: "guest_removed",
          old_value: { "name" => @booking_guest.name_snapshot, "email" => @booking_guest.email_snapshot,
            "phone" => @booking_guest.phone_snapshot, "country" => @booking_guest.country_snapshot }, new_value: {})
      end
      OpenStruct.new(success?: true, error: nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError => e
      failure("Guest removal was blocked to preserve financial history: #{e.message}")
    end

    private

    def failure(error) = OpenStruct.new(success?: false, error: error)
  end
end
