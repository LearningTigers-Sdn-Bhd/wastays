# frozen_string_literal: true

module ChannelManagers
  # Materializes the booking relationships required by the booking workspace.
  # Channel payloads often omit identity details that are only collected at
  # check-in, so newly-created guest profiles are marked incomplete rather than
  # leaving the booking disconnected.
  class InitializeBookingConnections
    def self.call!(booking:, guest_details:)
      new(booking:, guest_details:).call!
    end

    def initialize(booking:, guest_details:)
      @booking = booking
      @hotel = booking.hotel
      @guest_details = guest_details.to_h.symbolize_keys
    end

    def call!
      booking_guest = ensure_primary_guest!
      folio = Folios::Lifecycle::InitializeForBooking.call(
        booking: @booking,
        user: nil,
        options: { system_folio_initialization: true },
        lock: false
      )
      BookingBillingParties::EnsureForBooking.call(booking: @booking)
      folio.reload

      raise "Booking primary folio is missing its guest billing party." if folio.booking_billing_party_id.blank?

      { booking_guest:, billing_party: folio.booking_billing_party, folio: }
    end

    private

    def ensure_primary_guest!
      existing = @booking.booking_guests.find_by(role: "primary")
      return existing if existing

      guest = find_guest || create_guest!
      @booking.booking_guests.create!(guest:, is_primary: true)
    end

    def find_guest
      government_id = @guest_details[:government_id].to_s.downcase.strip.presence
      return Guest.find_by(government_id:) if government_id

      email = @guest_details[:email].to_s.downcase.strip.presence
      return Guest.find_by(email:) if email

      phone = @guest_details[:phone].to_s.strip.presence
      Guest.find_by(phone:) if phone
    end

    def create_guest!
      date_of_birth = @guest_details[:date_of_birth].presence
      metadata = {
        "profile_source" => "channel_manager",
        "profile_incomplete" => date_of_birth.blank?
      }

      Guest.create!(
        name: @guest_details[:name],
        email: @guest_details[:email],
        phone: @guest_details[:phone],
        government_id: @guest_details[:government_id],
        country: @guest_details[:country].presence || @hotel.country,
        gender: @guest_details[:gender],
        document_type: @guest_details[:document_type],
        date_of_birth: date_of_birth,
        metadata: metadata,
        created_by_hotel: @hotel
      )
    end
  end
end
