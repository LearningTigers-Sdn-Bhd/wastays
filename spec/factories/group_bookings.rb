# frozen_string_literal: true

FactoryBot.define do
  factory :group_booking do
    association :hotel
    name { "Conference Group" }
    status { "active" }
  end
end
