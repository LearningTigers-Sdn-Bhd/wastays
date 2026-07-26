# frozen_string_literal: true

module Folios
  # Inserts the booking's primary folio — sequence 1, is_primary — routed to the
  # booking's agent when one is linked, and to the guest otherwise.
  #
  # The plain insert only: no lock, no rescue, no operational guard. The caller
  # owns the transaction and decides how to recover from a concurrent insert,
  # because the two races differ: an unlocked caller inside its own transaction
  # cannot rescue a duplicate insert without poisoning that transaction.
  class BuildPrimaryFolio
    def self.call(booking:, actor:, hotel: booking.hotel)
      new(booking: booking, actor: actor, hotel: hotel).call
    end

    def initialize(booking:, actor:, hotel: booking.hotel)
      @booking = booking
      @actor = actor
      @hotel = hotel
    end

    def call
      folio_number = Folios::NextFolioNumber.call(hotel: @hotel)
      @booking.assign_folio_account_reference_from!(folio_number)
      billing_party = agent_billing_party

      @booking.create_booking_folio!(
        hotel: @hotel,
        folio_number: folio_number,
        folio_sequence: 1,
        name: billing_party ? "Agent Folio" : "Guest Folio",
        folio_type: billing_party ? "external" : "guest",
        payer_type: billing_party ? "company" : "guest",
        hotel_corporate_account: billing_party&.hotel_corporate_account,
        booking_billing_party: billing_party,
        is_primary: true,
        currency: @booking.currency.presence || @hotel.default_currency,
        opened_at: Time.current,
        created_by: @actor
      )
    end

    private

    def agent_billing_party
      return unless @booking.hotel_corporate_account_id.present?

      hotel_corporate_account = @booking.hotel_corporate_account
      return unless hotel_corporate_account&.active?

      @booking.booking_billing_parties.find_or_create_by!(
        hotel_corporate_account: hotel_corporate_account
      ) do |party|
        party.hotel = @hotel
        party.party_kind = "company"
        party.account_type = hotel_corporate_account.account_type
      end
    end
  end
end
