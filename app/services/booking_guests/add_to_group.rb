# frozen_string_literal: true

module BookingGuests
  class AddToGroup
    Result = Data.define(:success?, :guest, :booking_guests, :errors)
    ELIGIBLE_STATUSES = %w[confirmed checked_in].freeze

    def self.call(group_booking:, attributes:, actor:)
      new(group_booking:, attributes:, actor:).call
    end

    def initialize(group_booking:, attributes:, actor:)
      @group_booking = group_booking
      @attributes = attributes
      @actor = actor
    end

    def call
      guest = Guest.new(@attributes)
      guest.created_by_hotel = @group_booking.hotel
      return Result.new(false, guest, [], guest.errors.full_messages) unless guest.valid?

      booking_guests = []
      ActiveRecord::Base.transaction do
        @group_booking.lock!
        bookings = @group_booking.bookings.order(:group_position, :id).lock.to_a
        ineligible = bookings.reject { |booking| booking.status.in?(ELIGIBLE_STATUSES) }
        if bookings.empty? || ineligible.any?
          labels = ineligible.map { |booking| booking.formatted_reservation_number.presence || booking.id }
          message = bookings.empty? ? "The group has no bookings." : "Guests cannot be added to: #{labels.to_sentence}."
          raise ActiveRecord::Rollback, message
        end

        guest.save!
        bookings.each do |booking|
          booking_guest = booking.booking_guests.create!(guest:, is_primary: false)
          booking_guests << booking_guest
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            user: @actor,
            action_type: "guest_added",
            old_value: {},
            new_value: guest.attributes.slice(*BookingGuests::Add::AUDIT_ATTRIBUTES)
          )
        end
      end

      return Result.new(false, guest, [], [ "Guest could not be added to every booking in the group." ]) unless guest.persisted?

      Result.new(true, guest, booking_guests, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, guest, [], e.record.errors.full_messages)
    end
  end
end
