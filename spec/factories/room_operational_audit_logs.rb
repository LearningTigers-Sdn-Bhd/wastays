FactoryBot.define do
  factory :room_operational_audit_log do
    association :hotel
    room_type { association :room_type, hotel: hotel }
    association :user
    room_number { "101" }
    event_type { "room_status_changed" }
    old_status { "dirty" }
    new_status { "ready" }
    reason { "Room inspected" }
    metadata { { "source" => "spec" } }
  end
end
