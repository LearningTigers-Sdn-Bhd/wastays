FactoryBot.define do
  factory :journal_batch_entry do
    association :journal_batch
    gl_code { "4010" }
    transaction_type { "charge" }
    debit_amount { 0 }
    credit_amount { 100.0 }
    description { "Test summary entry" }
  end
end
