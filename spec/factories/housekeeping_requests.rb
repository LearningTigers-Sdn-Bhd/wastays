FactoryBot.define do
  factory :housekeeping_request do
    booking
    # Letters only. external_id is one of the columns the board's search reads,
    # so a random hex id would now and then contain the digits a spec searches
    # for -- a room number, say -- and hand that spec an extra row.
    external_id { "EXT-#{Array.new(8) { ("A".."Z").to_a.sample }.join}" }
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
