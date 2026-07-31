# frozen_string_literal: true

module HousekeepingTasks
  # The cleaning a room needs once its guest has gone.
  #
  # Raised when the front desk actually completes the checkout, which is the
  # moment the room is empty -- not when a guest says they are leaving. Most
  # guests never say: they walk to the desk, settle the folio, and go. So this
  # hangs off the booking's own departure and nothing else.
  #
  # One task per room, because one task per booking would have a housekeeper
  # tick off a three-room party after cleaning one of them.
  class CreateTurnover
    # What a turnover is called, every time. Never a guest's own words: a guest
    # writing "late checkout until 2pm" into the concierge page is asking the
    # front desk for something, and a housekeeper handed that as their
    # instruction has been told nothing about the room.
    DETAILS = "Checkout turnover"

    def initialize(booking:, timestamp: Time.current)
      @booking = booking
      @timestamp = timestamp
    end

    def call
      return [] if @booking.nil?

      rooms.filter_map { |booking_room| turnover_for(booking_room) }
    end

    private

    def rooms
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ])
    end

    def turnover_for(booking_room)
      return if already_owed?(booking_room)

      HousekeepingRequest.create!(
        booking: @booking,
        hotel: @booking.hotel,
        room_type: booking_room.room_type,
        room_number: booking_room.room_number,
        work_context: "checkout_turnover",
        request_details: DETAILS,
        requested_at: @timestamp,
        status: "new",
        metadata: { "source" => "checkout_turnover" }
      )
    end

    # Checking out twice is not two cleanings. Asked per room rather than per
    # booking so a room added to a stay after an earlier departure still gets
    # its own.
    def already_owed?(booking_room)
      HousekeepingRequest
        .checkout_turnovers
        .open_tasks
        .where(booking_id: @booking.id, room_number: booking_room.room_number)
        .exists?
    end
  end
end
