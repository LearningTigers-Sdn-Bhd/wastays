# frozen_string_literal: true

module BookingGuests
  class UpdatePrimary
    Result = Data.define(:success?, :errors)

    def self.call(booking:, attributes:, actor:, bibo_attributes: {})
      new(booking:, attributes:, actor:, bibo_attributes:).call
    end

    def initialize(booking:, attributes:, actor:, bibo_attributes:)
      @booking = booking
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
      @bibo_attributes = bibo_attributes
    end

    def call
      candidate = primary_guest_record
      candidate.assign_attributes(@attributes)
      return Result.new(false, candidate.errors.full_messages) unless candidate.valid?

      errors = []
      committed = ActiveRecord::Base.transaction do
        result = Bookings::UpdateStayService.new(
          booking: @booking,
          params: primary_booking_params,
          user: @actor
        ).call
        unless result.success?
          errors.concat(result.errors)
          raise ActiveRecord::Rollback
        end

        @booking.reload.primary_guest&.update!(@attributes)
        booking_guest = @booking.booking_guests.find_by(is_primary: true)
        if booking_guest && !booking_guest.update(@bibo_attributes)
          errors.concat(booking_guest.errors.full_messages)
          raise ActiveRecord::Rollback
        end

        true
      end

      committed ? Result.new(true, []) : Result.new(false, errors)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, e.record.errors.full_messages)
    end

    private

    def primary_guest_record
      @booking.primary_guest || Guest.new(
        name: @booking.guest_name,
        email: @booking.guest_email,
        phone: @booking.guest_phone,
        country: @booking.guest_country,
        gender: @booking.guest_gender,
        document_type: @booking.guest_document_type,
        government_id: @booking.guest_government_id,
        date_of_birth: @booking.guest_date_of_birth
      )
    end

    def primary_booking_params
      {
        guest_name: @attributes[:name],
        guest_email: @attributes[:email],
        guest_phone: @attributes[:phone],
        guest_country: @attributes[:country],
        guest_gender: @attributes[:gender],
        guest_document_type: @attributes[:document_type],
        guest_government_id: @attributes[:government_id],
        guest_date_of_birth: @attributes[:date_of_birth]
      }
    end
  end
end
