FactoryBot.define do
  factory :setup_fee_rule do
    transient do
      hotel { nil }
    end

    amount { 500.0 }
    currency { SetupFeeRule::CURRENCY }
    status { "active" }
    settable { hotel || association(:hotel) }

    trait :global_default do
      settable { nil }
    end
  end
end
