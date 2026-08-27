# frozen_string_literal: true

module Bookings
  class ValidateStayProposal
    def self.call(booking:, room_type:, room_number:, check_in:, check_out:)
      new(booking:, room_type:, room_number:, check_in:, check_out:).call
    end

    def initialize(booking:, room_type:, room_number:, check_in:, check_out:)
      @booking = booking
      @room_type = room_type
      @room_number = room_number.to_s
      @check_in = check_in
      @check_out = check_out
    end

    def call
      errors = []
      errors << "Checkout must be after check-in." unless check_out > check_in
      errors << "Select a configured room." unless ::Rooms::DirectoryQuery.for_room_type(room_type).include?(room_number)
      return errors.freeze if errors.any?

      available = AvailableRoomNumbers.new(
        hotel: booking.hotel,
        room_type:,
        check_in:,
        check_out:,
        exclude_booking_id: booking.id
      ).call
      errors << "Room #{room_number} is not available for these dates." unless available.include?(room_number)
      errors.freeze
    end

    private

    attr_reader :booking, :room_type, :room_number, :check_in, :check_out
  end
end
