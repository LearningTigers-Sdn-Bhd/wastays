# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_boat_schedule do
    hotel
    kind { "boat_in" }
    time { "08:00" }
    has_breakfast { false }
    has_lunch { false }
    has_dinner { false }

    trait :archived do
      archived_at { Time.current }
    end
  end

  factory :hotel_boat_setting do
    hotel
    breakfast_time { "08:00" }
    lunch_time { "12:00" }
    dinner_time { "19:00" }
  end
end
