# frozen_string_literal: true

require "ostruct"

module Guests
  class BulkDestroyService
    def initialize(guest_ids:, hotel:)
      @guest_ids = guest_ids
      @hotel = hotel
    end

    def call
      # Retrieve and filter guests that belong to this hotel (safety check and same authorization as set_guest in controller)
      # Uses a single database query avoiding N+1 check in Ruby memory
      allowed_guests = Guest.kept
                            .where(id: @guest_ids)
                            .left_outer_joins(:bookings)
                            .where("guests.created_by_hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: @hotel.id)
                            .distinct

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
