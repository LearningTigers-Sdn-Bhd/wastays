# frozen_string_literal: true

require "ostruct"

module Guests
  class BulkDestroyService
    def initialize(guest_ids:, hotel:)
      @guest_ids = guest_ids
      @hotel = hotel
    end

    def call
      # One query, and the same rule the record page uses to decide whether this
      # property may read the guest at all.
      allowed_guests = Guest.kept.where(id: @guest_ids).for_hotel(@hotel)

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
