FactoryBot.define do
  factory :transaction_code do
    association :hotel
    sequence(:system_key) { |n| "custom_code_#{n}" }
    sequence(:code) { |n| "CODE#{n}" }
    name { "Custom Code" }
    kind { "charge" }
    category { "other" }
    active { true }
    system_required { false }
    gl_account_code { "4090" }
  end
end
