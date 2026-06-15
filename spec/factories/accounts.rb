FactoryBot.define do
  factory :account do
    name { "Account #{SecureRandom.hex(6)}" }
    status { "active" }
  end
end
