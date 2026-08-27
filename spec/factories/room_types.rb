FactoryBot.define do
  factory :room_type do
    association :hotel
    sequence(:name) { |n| "Deluxe #{n}" }
    description { "Spacious room with city view." }
    max_adults { 1 }
    max_children { 1 }
    quantity { 1 }
    base_price { 99.99 }
    room_number_mode { "range" }

    # Every room-number write in the application runs the sync, so a room type
    # built for a spec owns physical rooms too. The boards read them.
    #
    # Set `sync_rooms: false` to hold the two apart on purpose. Only a spec
    # about drift between the two sources needs that.
    transient { sync_rooms { true } }

    after(:create) do |room_type, evaluator|
      Rooms::SyncFromRoomType.call(room_type:) if evaluator.sync_rooms && room_type.room_numbers.any?
    end
  end
end
