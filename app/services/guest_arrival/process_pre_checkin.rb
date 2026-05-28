require "ostruct"

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
      submitted_arrival_time = @params.delete("estimated_arrival_time")
      signature_data = @params.delete("signature")

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
          country: @booking.guest_country,
          document_type: @booking.guest_document_type
        ).call

        primary_booking_guest = @booking.booking_guests.find_or_initialize_by(is_primary: true)
        primary_booking_guest.guest = guest_result.guest
        primary_booking_guest.save!

        @pre_checkin.update!(
          status: "completed",
          completed_at: Time.current,
          document_status: "verified",
          signature_status: "signed",
          metadata: (@pre_checkin.metadata || {}).merge(
            guest_government_id: submitted_government_id,
            estimated_arrival_time: submitted_arrival_time,
            submitted_at: Time.current.iso8601
          )
        )

        @booking.update!(pre_checkin_status: "completed")
        Bookings::RecordAuditLog.call(auditable: @booking, action_type: "pre_checkin_completed")
      end

      OpenStruct.new(success?: true)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      OpenStruct.new(
        success?: false,
        message: e.message,
        submitted_arrival_time: submitted_arrival_time,
        submitted_government_id: submitted_government_id
      )
    rescue => e
      OpenStruct.new(
        success?: false,
        message: "Pre-check-in failed: #{e.message}",
        submitted_arrival_time: submitted_arrival_time,
        submitted_government_id: submitted_government_id
      )
    end
  end
end
