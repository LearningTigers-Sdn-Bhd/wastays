# frozen_string_literal: true

require "ostruct"

module BookingBillingParties
  class UpdateTerms
    def self.call(party:, actor:, attributes:)
      new(party: party, actor: actor, attributes: attributes).call
    end

    def initialize(party:, actor:, attributes:)
      @party = party
      @actor = actor
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      terms = @party.billing_terms || @party.build_billing_terms(created_by: @actor)
      previous = terms.attributes.slice(*term_keys)
      terms.assign_attributes(@attributes.slice(*term_keys))
      terms.updated_by = @actor
      terms.save!
      BookingAuditLog.create!(hotel: @party.hotel, auditable: @party.booking, user: @actor,
        action_type: "billing_terms_updated", category: "financial", source: "booking_control_panel",
        occurred_at: Time.current, old_value: previous, new_value: terms.attributes.slice(*term_keys))
      OpenStruct.new(success?: true, terms: terms, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      OpenStruct.new(success?: false, terms: e.record, error: e.record.errors.full_messages.to_sentence)
    end

    private

    def term_keys
      %w[settlement_type purchase_order_reference authorization_reference]
    end
  end
end
