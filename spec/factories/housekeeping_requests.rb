FactoryBot.define do
  factory :housekeeping_request do
    booking
    external_id { "EXT-#{SecureRandom.hex(4)}" }
    requested_at { Time.current }
    request_details { "Please clean the room" }
    status { "pending" }
    # A guest request is asked for against a stay, so one without a booking is
    # not a guest request -- it is work raised on a room. Derived rather than
    # fixed so a spec that drops the booking does not quietly build a
    # contradiction.
    work_context { booking ? "guest_request" : "vacant_room_task" }
  end
end
