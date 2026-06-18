FactoryBot.define do
  factory :e_invoice_setting do
    association :hotel
    enabled { true }
    hotel_tin { "C1234567890" }
    hotel_brn { "202301012345" }
  end
end
