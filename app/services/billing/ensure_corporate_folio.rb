# frozen_string_literal: true

require "ostruct"

module Billing
  class EnsureCorporateFolio
    def self.call(booking:, arrangement:, actor: nil)
      new(booking: booking, arrangement: arrangement, actor: actor).call
    end

    def initialize(booking:, arrangement:, actor: nil)
      @booking = booking
      @arrangement = arrangement
      @actor = actor
    end

    def call
      error = validation_error
      return failure(error) if error

      folio = nil
      @booking.with_lock do
        party = ensure_billing_party!
        folio = @booking.booking_folios.find_by(
          payer_type: "company",
          hotel_corporate_account_id: @arrangement.hotel_corporate_account_id
        )
        folio ||= create_folio!(party)
        folio.update!(booking_billing_party: party) if folio.booking_billing_party_id != party.id
      end

      OpenStruct.new(success?: true, folio: folio)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validation_error
      return "Arrangement must use a company payer." unless @arrangement.payer_type == "company"
      return "Arrangement and booking must belong to the same group." unless @booking.group_booking_id == @arrangement.group_booking_id
      return "Corporate account is not active." unless @arrangement.hotel_corporate_account&.active?

      nil
    end

    def ensure_billing_party!
      party = @booking.booking_billing_parties.find_or_initialize_by(hotel_corporate_account: @arrangement.hotel_corporate_account)
      party.assign_attributes(hotel: @booking.hotel, party_kind: "company", archived_at: nil)
      party.created_by ||= @actor
      party.save!
      terms = party.billing_terms || party.build_billing_terms(created_by: @actor)
      terms.assign_attributes(
        settlement_type: @arrangement.settlement_type,
        preferred_payment_method: @arrangement.preferred_payment_method,
        purchase_order_reference: @arrangement.purchase_order_reference,
        billing_reference: @arrangement.billing_reference,
        authorization_reference: @arrangement.authorization_reference,
        updated_by: @actor
      )
      terms.save!
      party
    end

    def create_folio!(party)
      account_name = @arrangement.hotel_corporate_account.corporate_account.name
      counter_number = HotelCounter.increment!(hotel: @booking.hotel, type: "folio")
      existing_maximum = BookingFolio.where(hotel: @booking.hotel).maximum(:folio_number).to_i
      folio_number = [ counter_number, existing_maximum + 1 ].max
      @booking.booking_folios.create!(
        hotel: @booking.hotel,
        folio_number: folio_number,
        folio_sequence: @booking.booking_folios.maximum(:folio_sequence).to_i + 1,
        name: account_name,
        folio_type: "external",
        payer_type: "company",
        hotel_corporate_account: @arrangement.hotel_corporate_account,
        booking_billing_party: party,
        is_primary: false,
        status: "open",
        currency: @booking.currency,
        opened_at: Time.current,
        created_by: @actor
      )
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, folio: nil)
    end
  end
end
