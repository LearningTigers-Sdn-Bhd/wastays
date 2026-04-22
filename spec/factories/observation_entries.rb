FactoryBot.define do
  factory :observation_entry do
    entry_type { "request" }
    request_id { SecureRandom.uuid }
    status { 200 }
    duration { 10.5 }
    path { "GET /test" }
    payload { { key: "value" } }
    tags { [] }
  end
end
