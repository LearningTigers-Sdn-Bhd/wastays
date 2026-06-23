FactoryBot.define do
  factory :transaction_code_tax do
    association :transaction_code
    association :hotel_tax
  end
end
