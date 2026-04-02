FactoryBot.define do
  factory :banking_detail do
    association :account
    account_holder_name { 'Syarikat Maju Jaya Sdn Bhd' }
    bank_name { 'Maybank' }
    account_number { '5142 1234 5678' }
    account_type { 'current' }
  end
end
