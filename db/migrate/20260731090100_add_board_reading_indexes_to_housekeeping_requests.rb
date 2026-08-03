# frozen_string_literal: true

# The requests board reads a housekeeping request by its hotel and orders it by
# when it was asked for, or -- in the completed column -- by when it was
# finished. It has indexes pairing hotel_id with status and with room_number,
# and pairing booking_id with requested_at, but none for either of the pairs it
# actually reads a column through.
#
# Both halves of HousekeepingRequest.in_hotel need covering: a request raised at
# the desk carries its own hotel_id, and one a guest raised on the concierge page
# reaches the hotel only through its booking.
class AddBoardReadingIndexesToHousekeepingRequests < ActiveRecord::Migration[8.0]
  def change
    add_index :housekeeping_requests, [ :hotel_id, :requested_at ]
    add_index :housekeeping_requests, [ :hotel_id, :completed_at ]
    add_index :housekeeping_requests, [ :booking_id, :completed_at ]
  end
end
