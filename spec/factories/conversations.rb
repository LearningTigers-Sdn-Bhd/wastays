FactoryBot.define do
  factory :conversation do
    association :hotel
    prospect { association :prospect, hotel: hotel }
    channel { "web" }
    mode { "bot" }
    status { "open" }

    trait :whatsapp do
      channel { "whatsapp" }
    end

    trait :with_human do
      mode { "human" }
      association :assigned_user, factory: :user
    end

    trait :closed do
      status { "closed" }
      closed_at { Time.current }
    end
  end
end
