FactoryBot.define do
  factory :rate_plan do
    name { "Standard Rate" }
    association :hotel
    sell_mode { "per_room" }
    currency { "MYR" }
    # Mirrors the default name. Specs that override :name to an ordinary plan
    # should pass kind: "custom" (or use the :custom trait) so the record is
    # deletable and archivable the way a hotelier-created plan is.
    kind { "standard" }

    trait :custom do
      name { "Promo Rate" }
      kind { "custom" }
    end

    trait :walk_in_tier do
      name { "Walk-in Rate" }
      kind { "walk_in" }
    end

    trait :corporate_tier do
      name { "Corporate Rate" }
      kind { "corporate" }
    end

    trait :ota_tier do
      name { "OTA Rate" }
      kind { "ota" }
    end

    transient do
      room_type { nil }
    end

    after(:create) do |rate_plan, evaluator|
      if evaluator.room_type
        create(:room_type_rate_plan, rate_plan: rate_plan, room_type: evaluator.room_type)
      end
    end

    trait :age_banded do
      sell_mode { "per_person" }

      after(:create) do |rate_plan|
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child")
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 12, max_age: 17, price_value: 20, label: "Teen")
      end
    end
  end
end
