FactoryBot.define do
  factory :room_operational_audit_log do
    association :hotel
    association :room_type
    association :user
    room_number { "101" }
    event_type { "room_status_changed" }
    old_status { "dirty" }
    new_status { "ready" }
    reason { "Room inspected" }
    metadata { { "source" => "spec" } }

    after(:build) do |log|
      log.room_type.hotel = log.hotel if log.room_type && log.hotel
    end
  end
end
