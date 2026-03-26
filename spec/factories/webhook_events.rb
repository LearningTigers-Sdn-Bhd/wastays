FactoryBot.define do
  factory :webhook_event do
    gateway { "MyString" }
    external_id { "MyString" }
    payload { "" }
    status { "MyString" }
    error_message { "MyText" }
    processed_at { "2026-03-26 11:43:25" }
  end
end
