# frozen_string_literal: true

require "ostruct"

module Guests
  class BulkDestroyService
    def initialize(guest_ids:, hotel:)
      @guest_ids = guest_ids
      @hotel = hotel
    end

    def call
      # Retrieve guests that belong to this hotel (safety check)
      guests = Guest.kept.where(id: @guest_ids)

      # Filter to ensure they are either created by this hotel or have bookings at this hotel (same authorization as set_guest in controller)
      allowed_guests = guests.select do |guest|
        guest.created_by_hotel_id == @hotel.id || guest.bookings.where(hotel_id: @hotel.id).exists?
      end

      if allowed_guests.empty?
        return OpenStruct.new(success?: false, message: "No valid guest records selected for deletion.")
      end

      Guest.transaction do
        allowed_guests.each(&:discard!)
      end

      OpenStruct.new(success?: true, message: "Selected guest records removed successfully.")
    rescue => e
      OpenStruct.new(success?: false, message: "Failed to remove selected guests: #{e.message}")
    end
  end
end
