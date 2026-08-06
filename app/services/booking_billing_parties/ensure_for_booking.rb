# frozen_string_literal: true

module BookingBillingParties
  class EnsureForBooking
    def self.call(booking:, actor: nil)
      new(booking: booking, actor: actor).call
    end

    def initialize(booking:, actor: nil)
      @booking = booking
      @hotel = booking.hotel
      @actor = actor
    end

    def call
      BookingBillingParty.transaction do
        ensure_guest_parties!
        ensure_company_parties!
        link_unambiguous_legacy_guest_folios!
      end

      @booking.booking_billing_parties.active.includes(:booking_guest, hotel_corporate_account: :corporate_account).to_a
    end

    private

    def ensure_guest_parties!
      @booking.booking_guests.find_each do |booking_guest|
        ensure_party!(booking_guest: booking_guest, party_kind: "guest")
      end
    end

    def ensure_company_parties!
      company_folios.find_each do |folio|
        party = ensure_party!(hotel_corporate_account: folio.hotel_corporate_account, party_kind: "company")

        folio.update!(booking_billing_party: party) if folio.booking_billing_party_id.blank?
      end
    end

    def link_unambiguous_legacy_guest_folios!
      guest_party = unambiguous_guest_party
      return if guest_party.blank?

      @booking.booking_folios.where(booking_billing_party_id: nil, payer_type: "guest").find_each do |folio|
        folio.update!(booking_billing_party: guest_party)
      end
    end

    def company_folios
      @booking.booking_folios.where(payer_type: "company").where.not(hotel_corporate_account_id: nil)
    end

    def unambiguous_guest_party
      guest_parties = @booking.booking_billing_parties.guests.active.to_a
      guest_parties.one? ? guest_parties.first : nil
    end

    def ensure_party!(attributes)
      party = @booking.booking_billing_parties.find_or_initialize_by(attributes.except(:party_kind))
      party.hotel = @hotel
      party.party_kind = attributes.fetch(:party_kind)
      party.created_by ||= @actor
      party.archived_at = nil
      party.save!
      party.create_billing_terms!(created_by: @actor, updated_by: @actor) unless party.billing_terms
      party
    rescue ActiveRecord::RecordNotUnique
      retry_party = @booking.booking_billing_parties.find_by!(attributes.except(:party_kind))
      retry_party.update!(archived_at: nil) if retry_party.archived_at.present?
      retry_party
    end
  end
end
