FactoryBot.define do
  factory :hotel_general_ledger_map do
    association :hotel
    transaction_category { "accommodation" }
    gl_code { "4010" }
    description { "Room Revenue" }
  end
end
