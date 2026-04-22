FactoryBot.define do
  factory :payout_batch do
    association :hotel
    amount { 999.99 }
    status { "pending" }
    period_start { 7.days.ago.to_date }
    period_end { Date.current }
    payout_at { nil }
    sequence(:payout_reference) { |n| "PB-#{n}" }
    metadata { {} }
  end
end
