# frozen_string_literal: true

module BookingGuests
  class AddToGroup
    Result = Data.define(:success?, :guest, :booking_guests, :errors)
    ELIGIBLE_STATUSES = %w[confirmed checked_in].freeze

    def self.call(group_booking:, attributes:, actor:, existing_guest: nil, update_profile: false)
      new(group_booking:, attributes:, actor:, existing_guest:, update_profile:).call
    end

    def initialize(group_booking:, attributes:, actor:, existing_guest: nil, update_profile: false)
      @group_booking = group_booking
      @attributes = attributes
      @actor = actor
      @existing_guest = existing_guest
      @update_profile = update_profile
    end

    def call
      guest = @existing_guest || Guest.new
      # A picked record is validated on a copy, so the typed values are checked
      # before they reach the snapshots and the record itself changes only on
      # request.
      candidate = guest.persisted? ? guest.dup : guest
      candidate.assign_attributes(@attributes)
      candidate.created_by_hotel = @group_booking.hotel unless guest.persisted?
      return Result.new(false, candidate, [], candidate.errors.full_messages) unless candidate.valid?

      normalized = candidate.attributes.symbolize_keys.slice(*BookingGuests::Add::SNAPSHOT_ATTRIBUTES)

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

        if guest.persisted?
          guest.update!(normalized) if @update_profile
        else
          guest.save!
        end
        bookings.each do |booking|
          next if booking.booking_guests.exists?(guest_id: guest.id)

          booking_guest = booking.booking_guests.create!(
            guest:, is_primary: false, **BookingGuests::Add.snapshot_updates(normalized)
          )
          booking_guests << booking_guest
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            user: @actor,
            action_type: "guest_added",
            old_value: {},
            new_value: normalized.stringify_keys.slice(*BookingGuests::Add::AUDIT_ATTRIBUTES)
          )
        end
      end

      return Result.new(false, candidate, [], [ "Guest could not be added to every booking in the group." ]) unless guest.persisted?

      Result.new(true, guest, booking_guests, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, candidate, [], e.record.errors.full_messages)
    end
  end
end
