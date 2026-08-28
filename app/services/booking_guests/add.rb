# frozen_string_literal: true

module BookingGuests
  class Add
    Result = Data.define(:success?, :guest, :booking_guest, :errors)
    AUDIT_ATTRIBUTES = %w[name email phone country gender document_type date_of_birth home_address].freeze

    def self.call(booking:, attributes:, actor:)
      new(booking:, attributes:, actor:).call
    end

    def initialize(booking:, attributes:, actor:)
      @booking = booking
      @attributes = attributes
      @actor = actor
    end

    def call
      guest = Guest.new(@attributes)
      guest.created_by_hotel = @booking.hotel
      return Result.new(false, guest, nil, guest.errors.full_messages) unless guest.valid?

      booking_guest = nil
      ActiveRecord::Base.transaction do
        guest.save!
        booking_guest = @booking.booking_guests.create!(guest:, is_primary: false)
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "guest_added",
          old_value: {},
          new_value: guest.attributes.slice(*AUDIT_ATTRIBUTES)
        )
      end

      Result.new(true, guest, booking_guest, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, guest, booking_guest, e.record.errors.full_messages)
    end
  end
end
