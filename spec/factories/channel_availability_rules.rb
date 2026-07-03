# frozen_string_literal: true

FactoryBot.define do
  factory :channel_availability_rule do
    association :hotel
    title { "PMS Override" }
    start_date { Date.current }
    end_date { Date.current + 7.days }
    rule_type { "max_availability" }
    value { 3 }
    days { "mo,tu,we,th,fr,sa,su" }
    affected_channels { ["test_channel"] }
    affected_room_types { [1] }
  end
end
