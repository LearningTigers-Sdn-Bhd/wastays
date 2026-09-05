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
        synchronize_booking_guest_fields!
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

    def synchronize_booking_guest_fields!
      @booking.update!(
        guest_name: @booking_guest.name_snapshot,
        guest_email: @booking_guest.email_snapshot,
        guest_phone: @booking_guest.phone_snapshot,
        guest_country: @booking_guest.country_snapshot,
        guest_city: @booking_guest.city_snapshot,
        guest_state_code: @booking_guest.state_code_snapshot,
        guest_postal_code: @booking_guest.postal_code_snapshot,
        guest_address_country: @booking_guest.address_country_snapshot,
        guest_gender: @booking_guest.gender_snapshot,
        guest_document_type: @booking_guest.document_type_snapshot,
        guest_government_id: @booking_guest.government_id_snapshot,
        guest_passport_number: @booking_guest.safely_read_encrypted(:passport_number_snapshot),
        guest_date_of_birth: @booking_guest.date_of_birth_snapshot,
        guest_home_address: @booking_guest.home_address_snapshot
      )
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, booking_guest: nil)
    end
  end
end
