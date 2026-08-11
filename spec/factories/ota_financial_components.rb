# frozen_string_literal: true

FactoryBot.define do
  factory :ota_financial_component do
    association :ota_financial_snapshot
    booking do
      ota_financial_snapshot.booking || FactoryBot.build(
        :booking,
        hotel: ota_financial_snapshot.hotel,
        group_booking: ota_financial_snapshot.group_booking
      )
    end
    booking_room do
      FactoryBot.build(
        :booking_room,
        booking: booking,
        room_type: FactoryBot.build(:room_type, hotel: ota_financial_snapshot.hotel)
      )
    end
    transaction_code do
      FactoryBot.build(:transaction_code, hotel: ota_financial_snapshot.hotel, kind: "charge", category: "accommodation")
    end
    component_kind { "accommodation" }
    sequence(:stable_key) { |n| "rooms/0/days/0/accommodation/#{n}" }
    stay_date { booking.check_in.to_date }
    provider_name { "Room charge" }
    provider_type { "accommodation" }
    normalized_provider_name { "room_charge" }
    normalized_provider_type { "accommodation" }
    original_currency { ota_financial_snapshot.original_currency }
    original_amount { 200.to_d }
    currency { ota_financial_snapshot.currency }
    amount { 200.to_d }
    gross_effect_amount { 200.to_d }
    posting_amount { 200.to_d }
    mapping_status { "canonical" }
  end
end
