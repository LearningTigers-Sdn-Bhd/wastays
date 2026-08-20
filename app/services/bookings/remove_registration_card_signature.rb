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
      @card.remove_signature_for_guest!
    end
  end
end
