FactoryBot.define do
  factory :refund_request do
    association :booking
    reason { "Change of plans" }
    bank_name { "Maybank" }
    account_holder_name { "Ahmad Bin Ali" }
    account_number { "1234567890" }
    account_type { "savings" }
    status { "pending" }
    refund_amount { 160.0 }
  end
end
