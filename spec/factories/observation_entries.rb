FactoryBot.define do
  factory :observation_entry do
    entry_type { "MyString" }
    request_id { "MyString" }
    status { 1 }
    duration { 1.5 }
    path { "MyString" }
    payload { "" }
  end
end
