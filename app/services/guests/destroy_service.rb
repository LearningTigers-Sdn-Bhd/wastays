# frozen_string_literal: true

require "ostruct"

module Guests
  class DestroyService
    def initialize(guest:, hotel:)
      @guest = guest
      @hotel = hotel
    end

    def call
      # 1. Check if guest has any ACTIVE (non-cancelled) bookings at this hotel
      if @guest.bookings.where(hotel_id: @hotel.id).where.not(status: "cancelled").exists?
        return OpenStruct.new(
          success?: false,
          message: "Guest cannot be deleted because they have associated active bookings. Please cancel or remove bookings first if necessary."
        )
      end

      Guest.transaction do
        # Remove the links (BookingGuest) for this hotel
        @guest.booking_guests.joins(:booking).where(bookings: { hotel_id: @hotel.id }).destroy_all

        # If the guest was created by this hotel and has no more links anywhere else, delete the profile
        if @guest.created_by_hotel_id == @hotel.id && @guest.booking_guests.empty?
          @guest.destroy!
        end
      end

      OpenStruct.new(success?: true, message: "Guest record removed successfully.")
    rescue => e
      OpenStruct.new(success?: false, message: "Failed to remove guest: #{e.message}")
    end
  end
end
