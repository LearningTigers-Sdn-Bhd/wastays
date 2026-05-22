FactoryBot.define do
  factory :check_out_request do
    association :booking
    status { "pending" }
    requested_at { Time.current }
    metadata { {} }
  end
end
