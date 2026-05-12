# frozen_string_literal: true

FactoryBot.define do
  factory :room_block do
    hotel
    room_type
    room_number { "101" }
    start_date { Date.current }
    end_date { Date.current + 1.day }
    block_type { "maintenance" }
    reason { "Leaky faucet" }
    user
  end
end
