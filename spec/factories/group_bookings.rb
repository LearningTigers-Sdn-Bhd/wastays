# frozen_string_literal: true

FactoryBot.define do
  factory :group_booking do
    association :hotel
    sequence(:reference) { |n| "GRP-#{n}" }
    name { "Conference Group" }
    status { "active" }
  end
end
