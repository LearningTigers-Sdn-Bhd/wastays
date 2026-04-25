# frozen_string_literal: true

require "ostruct"

module Bookings
  class CreateManualBooking
    def initialize(hotel:, params:)
      @hotel = hotel
      @params = params.dup
      @room_type_id = @params.delete(:room_type_id)
      @room_number = @params.delete(:room_number)
    end

    def call
      booking = @hotel.bookings.build(@params)
      room_type = @hotel.room_types.find(@room_type_id)

      booking.status = "confirmed"
      booking.payment_status = "captured"
      booking.hotel_snapshot = @hotel.as_json.merge("room_number" => @room_number)

      # Simple price calculation for manual bookings if not provided
      booking.total_amount ||= room_type.base_price * (booking.check_out - booking.check_in).to_i

      ActiveRecord::Base.transaction do
        if booking.save
          booking.booking_rooms.create!(
            room_type: room_type,
            quantity: 1,
            subtotal: booking.total_amount,
            room_type_snapshot: room_type.as_json
          )

          InventoryManager.new(booking).deduct
          OpenStruct.new(success?: true, booking: booking)
        else
          OpenStruct.new(success?: false, errors: booking.errors.full_messages)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, errors: [ e.message ])
    end
  end
end
