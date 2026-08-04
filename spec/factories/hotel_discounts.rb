FactoryBot.define do
  factory :hotel_discount do
    association :hotel
    transaction_code do
      association(:transaction_code, hotel: hotel, kind: "adjustment", category: "discount", gl_account_code: "5030")
    end
    pricing_type { "manual" }
    application_scope { "all_eligible_charges" }
    allow_amount_override { true }
    position { 1 }
  end
end
