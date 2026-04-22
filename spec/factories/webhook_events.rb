FactoryBot.define do
  factory :webhook_event do
    gateway { "toyyibpay" }
    sequence(:external_id) { |n| "evt_#{n}" }
    payload { {} }
    status { "pending" }
    error_message { nil }
    processed_at { nil }
  end
end
