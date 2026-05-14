FactoryBot.define do
  factory :exchange_rate do
    base_currency { "MYR" }
    currency_code { "USD" }
    rate { 0.21 }
    effective_at { Time.current }
    active { true }
    source { "manual" }
  end
end
