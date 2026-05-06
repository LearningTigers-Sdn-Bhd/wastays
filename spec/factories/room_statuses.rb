FactoryBot.define do
  factory :room_status do
    association :hotel
    association :room_type
    sequence(:room_number) { |n| "#{100 + n}" }
    status { "ready" }
    last_changed_at { Time.current }

    after(:build) do |room_status|
      room_status.room_type.hotel = room_status.hotel if room_status.room_type && room_status.hotel
    end
  end
end
