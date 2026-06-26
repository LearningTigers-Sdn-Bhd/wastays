# frozen_string_literal: true

require "base64"
require "stringio"

module Concierge
  class CheckInForm
    include ActiveModel::Model

    attr_accessor :booking, :guest_name, :guest_email, :guest_phone, :guest_country,
                  :guest_document_type, :guest_government_id, :guest_home_address, :signature
    attr_writer :id_front, :id_back

    def id_front
      booking.id_front
    end

    def id_back
      booking.id_back
    end

    delegate :id, :to_param, :persisted?, to: :booking

    validates :guest_name, :guest_email, :guest_phone, :guest_country,
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
        old_value = booking.attributes.slice(*registration_keys)
        booking.update!(registration_attributes)
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
        public_send("#{key}=", current_value.presence || booking.public_send(key))
      end
    end

    def registration_keys
      %w[guest_name guest_email guest_phone guest_country guest_document_type guest_government_id guest_home_address]
    end

    def registration_attributes
      attrs = {
        guest_name: guest_name,
        guest_email: guest_email,
        guest_phone: guest_phone,
        guest_country: guest_country,
        guest_document_type: guest_document_type,
        guest_government_id: guest_government_id,
        guest_home_address: guest_home_address
      }
      attrs[:id_front] = @id_front if @id_front.present?
      attrs[:id_back] = @id_back if @id_back.present?
      attrs
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
      new_value = booking.attributes.slice(*registration_keys)
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
