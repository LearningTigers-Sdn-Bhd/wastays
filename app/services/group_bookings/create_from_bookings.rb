# frozen_string_literal: true

require "ostruct"

module GroupBookings
  class CreateFromBookings
    def self.call(hotel:, bookings:, attributes:, actor: nil)
      new(hotel: hotel, bookings: bookings, attributes: attributes, actor: actor).call
    end

    def initialize(hotel:, bookings:, attributes:, actor: nil)
      @hotel = hotel
      @bookings = Array(bookings).uniq
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      error = validation_error
      return failure(error) if error

      group_booking = nil
      GroupBooking.transaction do
        group_booking = @hotel.group_bookings.create!(@attributes)
        @bookings.sort_by(&:id).each.with_index(1) do |booking, position|
          booking.lock!
          booking.update!(group_booking: group_booking, group_position: position)
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            user: @actor,
            action_type: "update",
            category: "other",
            source: "group_booking",
            new_value: { group_booking_id: group_booking.id, group_position: position }
          )
        end
      end

      OpenStruct.new(success?: true, group_booking: group_booking)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validation_error
      return "At least two bookings are required." if @bookings.size < 2
      return "All bookings must belong to the selected hotel." unless @bookings.all? { |booking| booking.hotel_id == @hotel.id }
      return "Bookings already assigned to a group cannot be regrouped." if @bookings.any?(&:group_booking_id?)
      return "Every booking must contain exactly one room stay." unless @bookings.all? { |booking| one_room_stay?(booking) }

      nil
    end

    def one_room_stay?(booking)
      booking.booking_rooms.size == 1
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, group_booking: nil)
    end
  end
end
