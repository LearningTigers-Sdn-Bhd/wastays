# frozen_string_literal: true

FactoryBot.define do
  factory :room_group do
    association :hotel
    sequence(:name) { |n| "Wing #{n}" }
  end
end
