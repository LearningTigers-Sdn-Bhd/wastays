# frozen_string_literal: true

require "ostruct"

module BookingWorkspaces
  class CreateFolioWindow
    def self.call(booking:, user:, attributes: {})
      new(booking: booking, user: user, attributes: attributes).call
    end

    def initialize(booking:, user:, attributes: {})
      @booking = booking
      @hotel = booking.hotel
      @user = user
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      party = billing_party
      return failure("Select an active billing party for this booking.") if party.blank?

      result = ::Folios::Lifecycle::CreateFolio.call(
        booking: @booking,
        user: @user,
        attributes: folio_attributes(party)
      )
      return failure(result.error) unless result.success?

      success(result.folio)
    end

    private

    def billing_party
      @billing_party ||= @booking.booking_billing_parties.active.find_by(id: @attributes[:booking_billing_party_id])
    end

    def folio_attributes(party)
      common = {
        booking_billing_party_id: party.id,
        name: @attributes[:name].presence || default_name(party),
        currency: @attributes[:currency].presence,
        reason: @attributes[:reason].presence,
        is_primary: false
      }

      case party.party_kind
      when "guest"
        common.merge(folio_type: "guest", payer_type: "guest")
      when "company"
        common.merge(
          folio_type: "external",
          payer_type: "company",
          hotel_corporate_account_id: party.hotel_corporate_account_id
        )
      else
        common
      end
    end

    def default_name(party)
      case party.party_kind
      when "guest" then "#{party.display_name} Folio"
      when "company" then party.display_name
      else "Folio"
      end
    end

    def success(folio)
      OpenStruct.new(success?: true, folio: folio, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, folio: nil, error: error)
    end
  end
end
