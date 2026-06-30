# frozen_string_literal: true

require "ostruct"

class Guest::ToggleDndService
  def initialize(booking:)
    @booking = booking
  end

  def call
    unless @booking.status == "checked_in"
      return OpenStruct.new(
        success?: false,
        error: "Cannot toggle Do Not Disturb if you are not currently checked in."
      )
    end

    booking_rooms = @booking.booking_rooms.where.not(room_number: [ nil, "" ])
    if booking_rooms.empty?
      return OpenStruct.new(
        success?: false,
        error: "No room assigned to this booking."
      )
    end

    any_toggled = false
    booking_rooms.each do |br|
      room_status = RoomStatus.find_or_create_by!(
        hotel: @booking.hotel,
        room_type: br.room_type,
        room_number: br.room_number
      )

      new_dnd_state = !room_status.active_dnd?

      result = Rooms::UpdateStatus.new(
        room_status: room_status,
        params: { dnd: new_dnd_state.to_s },
        user: nil
      ).call

      any_toggled ||= result.success?
    end

    if any_toggled
      OpenStruct.new(
        success?: true,
        message: "Do Not Disturb preference updated successfully."
      )
    else
      OpenStruct.new(
        success?: false,
        error: "Unable to update Do Not Disturb preferences."
      )
    end
  end
end
