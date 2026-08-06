FactoryBot.define do
  factory :folio_transaction do
    association :booking_folio
    association :user
    amount { 100.0 }
    transaction_type { :charge }
    category { "accommodation" }
    posting_date { Date.current }
    description { "Test transaction" }
    currency { booking_folio&.booking&.currency || "MYR" }
  end
end
