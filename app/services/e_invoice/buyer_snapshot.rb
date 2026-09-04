# frozen_string_literal: true

module EInvoice
  class BuyerSnapshot
    def self.capture(booking)
      new(booking).capture
    end

    def initialize(booking)
      @booking = booking
      @booking_guest = booking.booking_guests.find(&:primary?)
      @address = PostalAddresses::Presenter.from_booking_guest(
        @booking_guest,
        fallback_booking: booking
      )
    end

    def capture
      address = @address.snapshot
      address_country = @booking_guest&.address_country_snapshot.presence || @booking.guest_address_country.presence
      raise ArgumentError, "Booking guest address country is required" if address_country.blank?
      raise ArgumentError, "Booking guest city is required" if address["city"].blank?
      address["country"] = address_country

      country_code = country_code_for(address_country)
      state_code = resolved_state_code(country_code)

      identity = EInvoice::GuestIdentityResolver.for_booking(@booking)
      raise ArgumentError, "Enter the guest's passport number before issuing an individual e-invoice." if identity.missing_passport?

      {
        "name" => @booking.guest_name,
        "contact_email" => @booking.guest_email,
        "contact_phone" => @booking.guest_phone,
        "tin" => @booking.buyer_tin_for_e_invoice,
        "government_id" => identity.document_number,
        "document_type" => identity.document_type,
        "nationality" => @booking.guest_country,
        "billing_address" => address.merge(
          "state_code" => state_code,
          "country_code" => country_code
        )
      }
    end

    private

    def country_code_for(country)
      ISO3166::Country.find_country_by_any_name(country)&.alpha3 || raise(ArgumentError, "Booking guest address country is invalid")
    end

    def resolved_state_code(country_code)
      return EInvoice::MalaysiaStates::NOT_APPLICABLE unless country_code == "MYS"

      EInvoice::MalaysiaStates.resolve(
        state_code: @booking_guest&.state_code_snapshot.presence || @booking.guest_state_code,
        city: @booking_guest&.city_snapshot.presence || @booking.guest_city,
        country_code: country_code
      ) || raise(ArgumentError, "Booking needs a buyer state before it can be filed with LHDN")
    end
  end
end
