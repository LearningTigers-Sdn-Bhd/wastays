# frozen_string_literal: true

module Bookings
  class RemoveRegistrationCardSignature
    def self.call(card:)
      new(card: card).call
    end

    def initialize(card:)
      @card = card
    end

    def call
      @card.update!(
        status: "draft",
        signer_name: nil,
        signature_data_url: nil,
        signed_at: nil,
        display_fields_snapshot: nil
      )
    end
  end
end
