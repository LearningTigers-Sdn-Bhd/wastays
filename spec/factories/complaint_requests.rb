FactoryBot.define do
  factory :complaint_request do
    booking
    external_id { "EXT-#{SecureRandom.hex(4)}" }
    requested_at { Time.current }
    complaint_details { "Water heater not working" }
    status { "pending" }
  end
end
