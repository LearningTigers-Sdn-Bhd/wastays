# frozen_string_literal: true

module Rooms
  class BoardBlocksQuery
    def initialize(hotel:, start_date:, end_date:)
      @hotel = hotel
      @start_date = start_date
      @end_date = end_date
    end

    def call
      @hotel.room_blocks
        .where(completed_at: nil)
        .for_date_range(@start_date, @end_date)
    end
  end
end
