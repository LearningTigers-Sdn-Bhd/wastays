# frozen_string_literal: true

module HotelPortal
  module RoomBlocksHelper
    def room_block_form_config(room_block, current_hotel)
      if room_block.new_record?
        {
          title: "Block Room",
          url: hotel_room_blocks_path(current_hotel),
          method: :post,
          submit_text: "Block Room"
        }
      else
        {
          title: "Edit Room Block",
          url: hotel_room_block_path(current_hotel, room_block),
          method: :patch,
          submit_text: "Update Block"
        }
      end
    end
  end
end
