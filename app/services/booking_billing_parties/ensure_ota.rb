# frozen_string_literal: true

module BookingBillingParties
  # Resolves the single OTA identity for a booking.  Booking sources are shared
  # registry records (they are not hotel-owned), so the booking is the tenant
  # boundary for the party and its hotel is always copied from the booking.
  class EnsureOta
    def self.call!(booking:, booking_source:, actor: nil)
      new(booking:, booking_source:, actor:).call!
    end

    def self.call(...)
      call!(...)
    end

    def initialize(booking:, booking_source:, actor: nil)
      @booking = booking
      @booking_source = booking_source
      @actor = actor
    end

    def call!
      validate!

      BookingBillingParty.transaction do
        @booking.with_lock do
          party = @booking.booking_billing_parties.lock.find_by(booking_source_id: @booking_source.id)
          party ||= @booking.booking_billing_parties.build(booking_source: @booking_source)
          party.assign_attributes(
            hotel: @booking.hotel,
            party_kind: "ota",
            booking_guest: nil,
            hotel_corporate_account: nil,
            account_type: nil,
            archived_at: nil
          )
          party.created_by ||= @actor
          party.save!
          party
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # The partial unique OTA identity index is the final arbiter when two
      # webhook deliveries race.  Re-read the winner and reactivate it.
      party = @booking.booking_billing_parties.find_by!(booking_source_id: @booking_source.id)
      party.update!(archived_at: nil) if party.archived_at.present?
      party
    end

    private

    def validate!
      raise ArgumentError, "Booking is required." unless @booking.is_a?(Booking) && @booking.persisted?
      raise ArgumentError, "Booking must belong to a hotel." if @booking.hotel_id.blank?
      unless @booking_source.is_a?(BookingSource) && @booking_source.persisted?
        raise ArgumentError, "Booking source is required."
      end
      if @booking_source.respond_to?(:hotel_id) && @booking_source.hotel_id.present? &&
          @booking_source.hotel_id != @booking.hotel_id
        raise ArgumentError, "Booking source must belong to the booking hotel."
      end
      return if @booking_source.kind == "ota"

      raise ArgumentError, "Booking source must be an OTA booking source."
    end
  end
end
