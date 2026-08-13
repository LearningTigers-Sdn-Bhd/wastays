# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_staff_draft do
    association :hotel
    role { association :role, account: hotel.account }
    name { "Draft Staff" }
    sequence(:email) { |number| "draft-staff-#{number}@example.com" }
  end
end
