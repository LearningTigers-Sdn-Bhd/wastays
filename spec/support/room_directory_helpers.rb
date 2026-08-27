# frozen_string_literal: true

# Room Inventory writes the JSON list and the physical rooms together. A spec
# that changes `room_numbers` directly must do the same, or the two sources
# drift and every board reads the stale one.
module RoomDirectoryHelpers
  def renumber_room_type!(room_type, numbers, **attributes)
    room_type.update!(quantity: numbers.size, room_numbers: numbers, **attributes)
    Rooms::SyncFromRoomType.call!(room_type:)
    room_type
  end
end

RSpec.configure do |config|
  config.include RoomDirectoryHelpers
end
