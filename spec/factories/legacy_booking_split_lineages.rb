# frozen_string_literal: true

FactoryBot.define do
  factory :legacy_booking_split_lineage do
    association :group_booking
    legacy_booking do
      association(:booking, hotel: group_booking.hotel, group_booking: group_booking, group_position: 1)
    end
    child_booking { legacy_booking }
    booking_room do
      association(:booking_room, booking: child_booking,
        room_type: association(:room_type, hotel: child_booking.hotel))
    end
    anchor { true }
    review_status { "approved" }
    review_reason { "automated legacy multi-room split" }
    batch_id { SecureRandom.uuid }
    metadata { {} }
  end
end
