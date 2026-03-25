FactoryBot.define do
  factory :property_policy do
    hotel { nil }
    check_in_time { "MyString" }
    check_out_time { "MyString" }
    cancellation_policy { "MyText" }
  end
end
