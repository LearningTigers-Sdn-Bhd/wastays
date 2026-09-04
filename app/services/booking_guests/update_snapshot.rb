# frozen_string_literal: true

module BookingGuests
  class UpdateSnapshot
    Result = Data.define(:success?, :errors)
    SNAPSHOT_ATTRIBUTES = %i[
      name email phone government_id passport_number gender country document_type
      date_of_birth home_address city state_code postal_code address_country
    ].freeze
    BIBO_ATTRIBUTES = %i[boat_in_at boat_out_at].freeze

    def self.call(booking_guest:, attributes:, actor:, update_profile: false, bibo_attributes: {})
      new(booking_guest:, attributes:, actor:, update_profile:, bibo_attributes:).call
    end

    def initialize(booking_guest:, attributes:, actor:, update_profile:, bibo_attributes:)
      @booking_guest = booking_guest
      @booking = booking_guest.booking
      @guest = booking_guest.guest
      @attributes = attributes.to_h.symbolize_keys.slice(*SNAPSHOT_ATTRIBUTES)
      @bibo_attributes = bibo_attributes.to_h.symbolize_keys.slice(*BIBO_ATTRIBUTES)
      @actor = actor
      @update_profile = update_profile
    end

    def call
      candidate = @guest.dup
      candidate.assign_attributes(@attributes)
      return Result.new(false, candidate.errors.full_messages) unless candidate.valid?

      normalized = candidate.attributes.symbolize_keys.slice(*SNAPSHOT_ATTRIBUTES)
      old_values = snapshot_values

      ActiveRecord::Base.transaction do
        @booking_guest.update!(snapshot_updates(normalized).merge(@bibo_attributes))
        update_primary_booking!(normalized) if @booking_guest.primary?
        @guest.update!(normalized) if @update_profile
        record_audit!(old_values, normalized)
      end

      Result.new(true, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, e.record.errors.full_messages)
    end

    private

    def snapshot_updates(values)
      values.to_h { |key, value| [ :"#{key}_snapshot", value ] }
    end

    def snapshot_values
      SNAPSHOT_ATTRIBUTES.to_h { |key| [ key.to_s, @booking_guest.public_send(:"#{key}_snapshot") ] }
        .merge(BIBO_ATTRIBUTES.to_h { |key| [ key.to_s, @booking_guest.public_send(key) ] })
    end

    def update_primary_booking!(values)
      @booking.update!(
        guest_name: values[:name],
        guest_email: values[:email],
        guest_phone: values[:phone],
        guest_country: values[:country],
        guest_city: values[:city],
        guest_state_code: values[:state_code],
        guest_postal_code: values[:postal_code],
        guest_address_country: values[:address_country],
        guest_gender: values[:gender],
        guest_document_type: values[:document_type],
        guest_government_id: values[:government_id],
        guest_passport_number: values[:passport_number],
        guest_date_of_birth: values[:date_of_birth],
        guest_home_address: values[:home_address]
      )
    end


    def record_audit!(old_values, values)
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: @actor,
        action_type: "guest_updated",
        old_value: old_values,
        new_value: values.stringify_keys.merge(@bibo_attributes.stringify_keys),
        metadata: { "save_scope" => @update_profile ? "snapshot_and_profile" : "snapshot" }
      )
    end
  end
end
