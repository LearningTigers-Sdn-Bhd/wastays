FactoryBot.define do
  factory :concierge_stay_access do
    association :hotel
    booking { association :booking, hotel: hotel, status: "checked_in" }

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :locked do
      attempt_count { ConciergeStayAccess::MAX_ATTEMPTS }
      attempt_window_started_at { Time.current }
      last_attempt_at { Time.current }
      locked_until { 1.hour.from_now }
    end
  end
end
