FactoryBot.define do
  factory :payment_setting do
    settable { nil }
    gateway { "MyString" }
    api_key { "MyString" }
    secret_key { "MyString" }
    webhook_secret { "MyString" }
    status { "MyString" }
  end
end
