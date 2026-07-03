# frozen_string_literal: true

require "ostruct"

module BookingBillingParties
  class ManageCompany
    def self.call(booking:, actor:, attributes:)
      new(booking: booking, actor: actor, attributes: attributes).call
    end

    def initialize(booking:, actor:, attributes:)
      @booking = booking
      @actor = actor
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      account = @booking.hotel.hotel_corporate_accounts.active.find_by(id: @attributes[:hotel_corporate_account_id])
      return failure("Select an active Company & Government Account.") unless account

      party = nil
      BookingBillingParty.transaction do
        party = @booking.booking_billing_parties.find_or_initialize_by(hotel_corporate_account: account)
        party.assign_attributes(hotel: @booking.hotel, party_kind: "company", archived_at: nil)
        party.created_by ||= @actor
        party.save!
        save_terms!(party)
        record_audit!(party)
      end
      success(party)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def save_terms!(party)
      terms = party.billing_terms || party.build_billing_terms(created_by: @actor)
      terms.assign_attributes(@attributes.slice(:settlement_type, :preferred_payment_method, :purchase_order_reference, :billing_reference, :authorization_reference))
      terms.updated_by = @actor
      terms.save!
    end

    def record_audit!(party)
      BookingAuditLog.create!(hotel: @booking.hotel, auditable: @booking, user: @actor,
        action_type: "billing_party_added", category: "financial", source: "booking_control_panel",
        occurred_at: Time.current, new_value: { billing_party_id: party.id, party: party.display_name })
    end

    def success(party) = OpenStruct.new(success?: true, party: party, error: nil)
    def failure(error) = OpenStruct.new(success?: false, party: nil, error: error)
  end
end
