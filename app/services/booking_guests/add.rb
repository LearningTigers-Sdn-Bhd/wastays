# frozen_string_literal: true

module BookingGuests
  class Add
    Result = Data.define(:success?, :guest, :booking_guest, :errors)
    AUDIT_ATTRIBUTES = %w[
      name email phone country gender document_type date_of_birth home_address
      city state_code postal_code address_country
    ].freeze
    # The stay keeps its own copy of the guest details. The desk can correct a
    # phone number for this stay without rewriting the person's record, so the
    # snapshot takes what was typed and the record changes only on request.
    SNAPSHOT_ATTRIBUTES = %i[
      name email phone government_id passport_number gender country document_type
      date_of_birth home_address city state_code postal_code address_country
    ].freeze

    def self.call(booking:, attributes:, actor:, existing_guest: nil, update_profile: false)
      new(booking:, attributes:, actor:, existing_guest:, update_profile:).call
    end

    def initialize(booking:, attributes:, actor:, existing_guest: nil, update_profile: false)
      @booking = booking
      @attributes = attributes
      @actor = actor
      @existing_guest = existing_guest
      @update_profile = update_profile
    end

    def call
      guest = @existing_guest || Guest.new
      # A picked record is validated on a copy. The typed values have to be
      # legal before they reach the snapshot, but the record itself must not
      # change unless the desk asked for it.
      candidate = guest.persisted? ? guest.dup : guest
      candidate.assign_attributes(@attributes)
      candidate.created_by_hotel = @booking.hotel unless guest.persisted?
      return Result.new(false, candidate, nil, candidate.errors.full_messages) unless candidate.valid?

      if guest.persisted? && @booking.booking_guests.exists?(guest_id: guest.id)
        return Result.new(false, candidate, nil, [ "#{guest.name} is already on this booking." ])
      end

      normalized = candidate.attributes.symbolize_keys.slice(*SNAPSHOT_ATTRIBUTES)

      booking_guest = nil
      ActiveRecord::Base.transaction do
        if guest.persisted?
          guest.update!(normalized) if @update_profile
        else
          guest.save!
        end
        booking_guest = @booking.booking_guests.create!(
          guest:, is_primary: false, **snapshot_updates(normalized)
        )
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "guest_added",
          old_value: {},
          new_value: normalized.stringify_keys.slice(*AUDIT_ATTRIBUTES)
        )
      end

      Result.new(true, guest, booking_guest, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, candidate, booking_guest, e.record.errors.full_messages)
    end

    def self.snapshot_updates(values)
      values.slice(*SNAPSHOT_ATTRIBUTES).to_h { |key, value| [ :"#{key}_snapshot", value ] }
    end

    private

    def snapshot_updates(values) = self.class.snapshot_updates(values)
  end
end
