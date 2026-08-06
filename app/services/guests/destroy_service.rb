# frozen_string_literal: true

require "ostruct"

module Guests
  class DestroyService
    def initialize(guest:, hotel:)
      @guest = guest
      @hotel = hotel
    end

    def call
      # We no longer block on active bookings because it is now a soft delete (discard).
      # The data remains in the database for existing bookings, but the guest is hidden from the directory.
      Guest.transaction do
        @guest.discard!
      end

      OpenStruct.new(success?: true, message: "Guest record removed successfully.")
    rescue => e
      OpenStruct.new(success?: false, message: "Failed to remove guest: #{e.message}")
    end
  end
end
