# frozen_string_literal: true

require "ostruct"
require "base64"
require "stringio"

module GuestArrival
  class ProcessPreCheckin
    def initialize(booking:, pre_checkin:, params:)
      @booking = booking
      @pre_checkin = pre_checkin
      @params = params.to_h
    end

    def call
      return OpenStruct.new(success?: false, message: "Pre-check-in was already completed.") if @pre_checkin.completed?

      submitted_government_id = @params.delete("guest_government_id")
      submitted_passport_number = @params.delete("guest_passport_number")
      submitted_arrival_time = @params.delete("estimated_arrival_time")
      submitted_date_of_birth = @params["guest_date_of_birth"]
      signature_data = @params.delete("signature")

      if signature_data.blank? || !signature_data.start_with?("data:image")
        return OpenStruct.new(
          success?: false,
          message: "Guest signature is required.",
          submitted_arrival_time: submitted_arrival_time,
          submitted_government_id: submitted_government_id,
          submitted_passport_number: submitted_passport_number,
          submitted_date_of_birth: submitted_date_of_birth
        )
      end

      missing_address_fields = %w[guest_home_address guest_city guest_address_country].select { |key| @params[key].blank? }
      if missing_address_fields.any?
        return OpenStruct.new(
          success?: false,
          message: "Street address, city, and address country are required.",
          submitted_arrival_time: submitted_arrival_time,
          submitted_government_id: submitted_government_id,
          submitted_passport_number: submitted_passport_number,
          submitted_date_of_birth: submitted_date_of_birth
        )
      end

      if @params["guest_address_country"].to_s.casecmp?("Malaysia")
        unless EInvoice::MalaysiaStates.valid?(@params["guest_state_code"])
          return OpenStruct.new(
            success?: false,
            message: "State is required for a Malaysian address.",
            submitted_arrival_time: submitted_arrival_time,
            submitted_government_id: submitted_government_id,
            submitted_passport_number: submitted_passport_number,
            submitted_date_of_birth: submitted_date_of_birth
          )
        end
      else
        @params["guest_state_code"] = EInvoice::MalaysiaStates::NOT_APPLICABLE
      end

      @booking.estimated_arrival_time = submitted_arrival_time

      ActiveRecord::Base.transaction do
        unless @booking.update(@params)
          raise ActiveRecord::RecordInvalid.new(@booking)
        end

        if signature_data.present? && signature_data.start_with?("data:image")
          format, img_64 = signature_data.split(",")
          decoded_data = Base64.decode64(img_64)
          @pre_checkin.signature.attach(
            io: StringIO.new(decoded_data),
            filename: "signature.png",
            content_type: "image/png"
          )
        end

        guest_result = GuestArrival::CreateOrMatchGuest.new(
          name: @booking.guest_name,
          email: @booking.guest_email,
          phone: @booking.guest_phone,
          government_id: submitted_government_id,
          passport_number: submitted_passport_number,
          city: @booking.guest_city,
          state_code: @booking.guest_state_code,
          postal_code: @booking.guest_postal_code,
          address_country: @booking.guest_address_country,
          home_address: @booking.guest_home_address,
          tin: @booking.guest_tin,
          country: @booking.guest_country,
          document_type: @booking.guest_document_type,
          date_of_birth: @booking.guest_date_of_birth
        ).call

        primary_booking_guest = @booking.booking_guests.find_or_initialize_by(is_primary: true)
        primary_booking_guest.guest = guest_result.guest
        primary_booking_guest.save!
        BookingGuests::CapturePrimaryStay.call(booking_guest: primary_booking_guest)

        @pre_checkin.update!(
          status: "completed",
          completed_at: Time.current,
          document_status: "verified",
          signature_status: "signed",
          metadata: (@pre_checkin.metadata || {}).merge(
            guest_government_id: submitted_government_id,
            guest_passport_number: submitted_passport_number,
            guest_date_of_birth: @booking.guest_date_of_birth,
            estimated_arrival_time: submitted_arrival_time,
            submitted_at: Time.current.iso8601
          )
        )

        @booking.update!(pre_checkin_status: "completed")
        Bookings::RecordAuditLog.call!(auditable: @booking, action_type: "pre_checkin_completed", source: "guest")
      end

      OpenStruct.new(success?: true)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      OpenStruct.new(
        success?: false,
        message: e.message,
        submitted_arrival_time: submitted_arrival_time,
        submitted_government_id: submitted_government_id,
        submitted_passport_number: submitted_passport_number,
        submitted_date_of_birth: submitted_date_of_birth
      )
    rescue => e
      OpenStruct.new(
        success?: false,
        message: "Pre-check-in failed: #{e.message}",
        submitted_arrival_time: submitted_arrival_time,
        submitted_government_id: submitted_government_id,
        submitted_passport_number: submitted_passport_number,
        submitted_date_of_birth: submitted_date_of_birth
      )
    end
  end
end
