# frozen_string_literal: true

require "base64"
require "stringio"

module Concierge
  class CheckInForm
    include ActiveModel::Model

    attr_accessor :booking, :guest_name, :guest_email, :guest_phone, :guest_country,
                  :guest_city, :guest_state_code, :guest_postal_code, :guest_address_country,
                  :guest_document_type, :guest_government_id, :guest_passport_number,
                  :guest_date_of_birth, :guest_home_address, :signature
    attr_writer :id_front, :id_back

    def id_front
      booking.id_front
    end

    def id_back
      booking.id_back
    end

    delegate :id, :to_param, :persisted?, to: :booking

    validates :guest_name, :guest_email, :guest_phone, :guest_country,
              :guest_city, :guest_address_country,
              :guest_document_type, :guest_government_id, :guest_home_address,
              presence: true, if: :needs_registration?

    def self.model_name
      ActiveModel::Name.new(self, nil, "Booking")
    end

    def initialize(booking:, params: {})
      @booking = booking
      super(params)
      assign_defaults
    end

    def save
      return true unless needs_registration?
      return false unless valid?

      Booking.transaction do
        old_value = registration_snapshot
        booking.update!(registration_attributes)
        sync_guest_profile!
        attach_signature

        # Transition pre-checkin status to completed
        pre_checkin = booking.pre_checkin || booking.create_pre_checkin!(
          status: "pending", document_status: "pending", signature_status: "pending"
        )
        pre_checkin.update!(
          status: "completed",
          completed_at: Time.current,
          document_status: "verified",
          signature_status: "signed"
        )
        booking.update!(pre_checkin_status: "completed")

        record_audit_log(old_value)
      end
      true
    rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing => e
      errors.add(:base, e.message)
      false
    end

    def needs_registration?
      booking.pre_checkin.nil? || !booking.pre_checkin.completed?
    end

    private

    def assign_defaults
      registration_keys.each do |key|
        current_value = public_send(key)
        public_send("#{key}=", current_value.presence || booking_value_for(key))
      end
    end

    def registration_keys
      %w[
        guest_name guest_email guest_phone guest_country guest_city guest_state_code
        guest_postal_code guest_address_country guest_document_type guest_government_id guest_passport_number
        guest_date_of_birth guest_home_address
      ]
    end

    def registration_attributes
      attrs = {
        guest_name: guest_name,
        guest_email: guest_email,
        guest_phone: guest_phone,
        guest_country: guest_country,
        guest_city: guest_city,
        guest_state_code: resolved_state_code,
        guest_postal_code: guest_postal_code,
        guest_address_country: guest_address_country,
        guest_document_type: guest_document_type,
        guest_government_id: guest_government_id,
        guest_passport_number: guest_passport_number,
        guest_date_of_birth: guest_date_of_birth,
        guest_home_address: guest_home_address
      }
      attrs[:id_front] = @id_front if @id_front.present?
      attrs[:id_back] = @id_back if @id_back.present?
      attrs
    end

    def booking_value_for(key)
      return booking.primary_guest&.date_of_birth if key == "guest_date_of_birth"

      booking.public_send(key)
    end

    def registration_snapshot
      registration_keys.index_with { |key| booking_value_for(key) }
    end

    def sync_guest_profile!
      guest_result = GuestArrival::CreateOrMatchGuest.new(
        name: booking.guest_name,
        email: booking.guest_email,
        phone: booking.guest_phone,
        government_id: booking.guest_government_id,
        passport_number: booking.guest_passport_number,
        city: booking.guest_city,
        state_code: booking.guest_state_code,
        postal_code: booking.guest_postal_code,
        address_country: booking.guest_address_country,
        home_address: booking.guest_home_address,
        country: booking.guest_country,
        document_type: booking.guest_document_type,
        date_of_birth: booking.guest_date_of_birth,
        created_by_hotel_id: booking.hotel_id
      ).call

      primary_booking_guest = booking.booking_guests.find_or_initialize_by(is_primary: true)
      primary_booking_guest.guest = guest_result.guest
      primary_booking_guest.save!
      BookingGuests::CapturePrimaryStay.call(booking_guest: primary_booking_guest)
    end

    def resolved_state_code
      return EInvoice::MalaysiaStates::NOT_APPLICABLE unless guest_address_country.to_s.casecmp?("Malaysia")

      guest_state_code
    end

    def attach_signature
      return if signature.blank? || !signature.start_with?("data:image")

      pre_checkin = booking.pre_checkin || booking.create_pre_checkin!(
        status: "pending", document_status: "pending", signature_status: "pending"
      )

      _format, encoded = signature.split(",")
      pre_checkin.signature.attach(
        io: StringIO.new(Base64.decode64(encoded)),
        filename: "signature.png",
        content_type: "image/png"
      )
      pre_checkin.update!(signature_status: "signed")
    end

    def record_audit_log(old_value)
      new_value = registration_snapshot
      Bookings::RecordAuditLog.call!(
        auditable: booking,
        action_type: "guest_updated",
        source: "guest",
        old_value: old_value,
        new_value: new_value,
        metadata: { "context" => "concierge_check_in" }
      )
    end
  end
end
