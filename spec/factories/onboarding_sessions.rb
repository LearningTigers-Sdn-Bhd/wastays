# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_session do
    association :hotel
    trainer_name { "Trainer Name" }
    scheduled_at { Time.current + 1.day }
    status { "scheduled" }
    notes { "Notes" }

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
    end
  end
end
