FactoryBot.define do
  factory :payment_setting do
    association :settable, factory: :hotel
    gateway { "razorpay" }
    api_key { "test_api_key" }
    secret_key { "test_secret_key" }
    webhook_secret { "test_webhook_secret" }
    status { "active" }
  end
end
