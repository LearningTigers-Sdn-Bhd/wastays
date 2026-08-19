# frozen_string_literal: true

module Bookings
  class RemoveRegistrationCardSignature
    def self.call(card:, booking_guest_id: nil)
      new(card: card, booking_guest_id: booking_guest_id).call
    end

    def initialize(card:, booking_guest_id: nil)
      @card = card
      @booking_guest_id = booking_guest_id
    end

    def call
      @card.remove_signature_for_guest!(booking_guest_id: @booking_guest_id)
    end
  end
end
