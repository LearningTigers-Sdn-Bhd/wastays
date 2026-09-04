# frozen_string_literal: true

require "ostruct"

module Guests
  # Sets the VIP flag on one or more guest records to an explicit value.
  #
  # VIP is a property of the guest record itself, not of one property, so this
  # service takes no hotel. The Guest model propagates the flag to the guest's
  # bookings after update, so each record is saved on its own.
  class SetVip
    def initialize(guests:, vip:)
      @guests = Array(guests)
      @vip = ActiveModel::Type::Boolean.new.cast(vip) || false
    end

    def call
      return empty_selection if @guests.empty?

      changed = @guests.reject { |guest| guest.vip? == @vip }
      return no_change if changed.empty?

      Guest.transaction do
        changed.each { |guest| guest.update!(vip: @vip) }
      end

      success(changed.size)
    rescue => e
      OpenStruct.new(success?: false, changed_count: 0, message: "Failed to update VIP status: #{e.message}")
    end

    private

    def empty_selection
      OpenStruct.new(success?: false, changed_count: 0, message: "No guest records selected.")
    end

    def no_change
      OpenStruct.new(success?: true, changed_count: 0, message: "No guest records needed a VIP change.")
    end

    def success(count)
      OpenStruct.new(success?: true, changed_count: count, message: success_message(count))
    end

    def success_message(count)
      noun = "guest record".pluralize(count)
      @vip ? "#{count} #{noun} marked as VIP." : "VIP removed from #{count} #{noun}."
    end
  end
end
