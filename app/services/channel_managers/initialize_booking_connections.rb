# frozen_string_literal: true

module ChannelManagers
  # Materializes the booking relationships required by the booking workspace.
  # Channel payloads often omit identity details that are only collected at
  # check-in, so newly-created guest profiles are marked incomplete rather than
  # leaving the booking disconnected.
  class InitializeBookingConnections
    # previous_guest_name is the guest the OTA named on the revision before
    # this one, which tells a real change of guest apart from a routine
    # revision of a booking whose profile staff have since chosen.
    def self.call!(booking:, guest_details:, previous_guest_name: nil)
      new(booking:, guest_details:, previous_guest_name:).call!
    end

    def initialize(booking:, guest_details:, previous_guest_name: nil)
      @booking = booking
      @hotel = booking.hotel
      @guest_details = guest_details.to_h.symbolize_keys
      @previous_guest_name = previous_guest_name
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
      if existing
        follow_guest_change!(existing)
        BookingGuests::CapturePrimaryStay.call(booking_guest: existing)
        return existing
      end

      guest = matcher.call || create_guest!
      booking_guest = @booking.booking_guests.create!(guest:, is_primary: true)
      BookingGuests::CapturePrimaryStay.call(booking_guest: booking_guest)
      booking_guest
    end

    # A later revision may name a different guest. A profile this channel made
    # for this booking alone, and nobody has completed since, simply takes the
    # new name. Any other profile belongs to someone, so the booking moves to
    # the right person's profile only when the OTA itself changed the guest
    # (a profile staff chose survives routine revisions), only before arrival
    # (after that the desk owns it), and only when the names share no word (a
    # respelling stays put).
    def follow_guest_change!(booking_guest)
      guest = booking_guest.guest
      name = @guest_details[:name].to_s.strip
      return if guest.nil? || name.blank? || MatchChannelGuest.same_name?(guest.name, name)

      if renamable?(guest)
        guest.update!(name: name)
      elsif ota_changed_guest?(name) && !arrived? && MatchChannelGuest.different_people?(guest.name, name)
        booking_guest.update!(guest: matcher.call || create_guest!)
      end
    end

    def ota_changed_guest?(name)
      @previous_guest_name.present? && !MatchChannelGuest.same_name?(@previous_guest_name, name)
    end

    def renamable?(guest)
      guest.metadata.to_h["profile_source"] == "channel_manager" &&
        guest.metadata.to_h["profile_incomplete"] &&
        !guest.booking_guests.where.not(booking_id: @booking.id).exists?
    end

    # Arrived, or started online pre-check-in: either way the profile now holds
    # what the guest themselves gave, so it is the desk's to change.
    def arrived?
      @booking.checked_in_at.present? ||
        !%w[pending confirmed overbooked].include?(@booking.status) ||
        %w[in_progress completed].include?(@booking.pre_checkin_status)
    end

    def matcher
      @matcher ||= MatchChannelGuest.new(@guest_details)
    end

    def create_guest!
      date_of_birth = @guest_details[:date_of_birth].presence
      metadata = {
        "profile_source" => "channel_manager",
        "profile_incomplete" => date_of_birth.blank?
      }

      # The booker's email and phone stay on the booking. They only go on the
      # profile when the booker is the guest staying.
      own_contact = matcher.contact_belongs_to_guest?

      Guest.create!(
        name: @guest_details[:name],
        email: (@guest_details[:email] if own_contact),
        phone: (@guest_details[:phone] if own_contact),
        government_id: @guest_details[:government_id],
        home_address: @guest_details[:home_address] || @guest_details[:address],
        city: @guest_details[:city],
        state_code: @guest_details[:state_code],
        postal_code: @guest_details[:postal_code],
        address_country: @guest_details[:address_country],
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
