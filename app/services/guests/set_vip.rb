# frozen_string_literal: true

require "ostruct"

module Guests
  # Marks or clears the VIP flag on one or more guest records for one property.
  #
  # A guest record is shared by every property the guest has booked with, so
  # VIP is stored per property. The property ids live in
  # `metadata["vip_hotel_ids"]`, and the `vip` column stays true while any
  # property still holds the flag. Guest#propagate_vip_status reads the list and
  # updates only that property's bookings.
  class SetVip
    def initialize(guests:, hotel:, vip:)
      @guests = Array(guests)
      @hotel = hotel
      @vip = ActiveModel::Type::Boolean.new.cast(vip) || false
    end

    def call
      return failure("No guest records selected.") if @guests.empty?
      return failure("No property selected.") if @hotel.blank?

      changed = @guests.reject { |guest| guest.vip_at?(@hotel) == @vip }
      return no_change if changed.empty?

      Guest.transaction do
        changed.each { |guest| apply(guest) }
      end

      success(changed.size)
    rescue => e
      failure("Failed to update VIP status: #{e.message}")
    end

    private

    def apply(guest)
      metadata = (guest.metadata || {}).deep_dup
      hotel_ids = normalized_hotel_ids(guest, metadata)

      @vip ? hotel_ids << @hotel.id : hotel_ids.delete(@hotel.id)

      metadata["vip_hotel_ids"] = hotel_ids.uniq
      guest.metadata = metadata
      guest.vip = metadata["vip_hotel_ids"].present?
      guest.save!
    end

    # A record marked VIP before the per-property list existed carries the
    # column alone, and Guest#vip_at? reads it at every property. Seed the list
    # from what that record already shows so no property loses the flag.
    def normalized_hotel_ids(guest, metadata)
      stored = metadata["vip_hotel_ids"]
      return stored.dup if stored.is_a?(Array) && stored.present?
      return [] unless guest[:vip]

      guest.bookings.distinct.pluck(:hotel_id).compact | [ guest.created_by_hotel_id ].compact
    end

    def no_change
      OpenStruct.new(success?: true, changed_count: 0, message: "No guest records needed a VIP change.")
    end

    def success(count)
      noun = "guest record".pluralize(count)
      message = @vip ? "#{count} #{noun} marked as VIP." : "VIP removed from #{count} #{noun}."
      OpenStruct.new(success?: true, changed_count: count, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, changed_count: 0, message: message)
    end
  end
end
