FactoryBot.define do
  factory :journal_batch do
    association :hotel
    business_date { Date.current }
    status { "finalized" }
    finalized_at { Time.current }
    summary_data { {} }
  end
end
