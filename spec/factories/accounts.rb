FactoryBot.define do
  factory :account do
    name { "Account #{SecureRandom.hex(6)}" }
    status { "active" }
    account_kind { "hotel" }

    trait :corporate do
      account_kind { "corporate" }
    end
  end
end
