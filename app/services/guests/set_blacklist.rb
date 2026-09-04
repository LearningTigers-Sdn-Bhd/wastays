# frozen_string_literal: true

require "ostruct"

module Guests
  # Blacklists or clears the blacklist on one or more guest records for one
  # property.
  #
  # A blacklist is per property. The property ids live in
  # `metadata["blacklisted_hotel_ids"]` and the audit trail lives in
  # `metadata["blacklist_details"]`, keyed by the property id as a string. The
  # `blacklisted` column stays true while any property still holds a blacklist.
  #
  # Older records were blacklisted before the metadata existed. They carry
  # `blacklisted = true` with no property ids, and Guest#blacklisted_at? reads
  # them through a fallback. Clearing such a record must leave the metadata
  # alone and only drop the column.
  class SetBlacklist
    def initialize(guests:, hotel:, blacklisted:, actor: nil, reason: nil)
      @guests = Array(guests)
      @hotel = hotel
      @blacklisted = ActiveModel::Type::Boolean.new.cast(blacklisted) || false
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      return failure("No guest records selected.") if @guests.empty?
      return failure("No property selected.") if @hotel.blank?
      return failure("Please provide a reason to blacklist this guest.") if @blacklisted && @reason.blank?

      changed = @guests.reject { |guest| guest.blacklisted_at?(@hotel) == @blacklisted }
      return no_change if changed.empty?

      Guest.transaction do
        changed.each { |guest| apply(guest) }
      end

      success(changed.size)
    rescue => e
      failure("Failed to update blacklist status: #{e.message}")
    end

    private

    def apply(guest)
      metadata = (guest.metadata || {}).deep_dup
      @blacklisted ? add(guest, metadata) : remove(guest, metadata)
      guest.metadata = metadata
      guest.save!
    end

    def add(guest, metadata)
      metadata["blacklisted_hotel_ids"] ||= []
      metadata["blacklisted_hotel_ids"] << @hotel.id
      metadata["blacklisted_hotel_ids"].uniq!
      metadata["blacklist_details"] ||= {}
      metadata["blacklist_details"][@hotel.id.to_s] = {
        "reason" => @reason,
        "blacklisted_by_id" => @actor&.id,
        "blacklisted_by_name" => @actor&.name,
        "blacklisted_at" => Time.current.iso8601
      }
      guest.blacklisted = true
    end

    def remove(guest, metadata)
      metadata["blacklisted_hotel_ids"].delete(@hotel.id) if metadata["blacklisted_hotel_ids"].is_a?(Array)
      metadata["blacklist_details"]&.delete(@hotel.id.to_s)
      guest.blacklisted = metadata["blacklisted_hotel_ids"].present?
    end

    def no_change
      OpenStruct.new(success?: true, changed_count: 0, message: "No guest records needed a blacklist change.")
    end

    def success(count)
      noun = "guest record".pluralize(count)
      message = @blacklisted ? "#{count} #{noun} blacklisted." : "Blacklist removed from #{count} #{noun}."
      OpenStruct.new(success?: true, changed_count: count, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, changed_count: 0, message: message)
    end
  end
end
