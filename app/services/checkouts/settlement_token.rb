# frozen_string_literal: true

module Checkouts
  class SettlementToken
    PURPOSE = :checkout_folio_settlement
    LIFETIME = 15.minutes

    def self.issue(booking:, folio:, kind:, amount:, adjustment: 0.to_d)
      verifier.generate(
        {
          booking_id: booking.id,
          folio_id: folio.id,
          kind: kind.to_s,
          amount: amount.to_d.abs.to_s("F"),
          adjustment: adjustment.to_d.to_s("F")
        },
        expires_in: LIFETIME,
        purpose: PURPOSE
      )
    end

    def self.verify(token)
      verifier.verify(token, purpose: PURPOSE).with_indifferent_access
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
