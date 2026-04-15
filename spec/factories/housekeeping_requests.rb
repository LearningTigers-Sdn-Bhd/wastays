FactoryBot.define do
  factory :housekeeping_request do
    booking
    external_id { "EXT-#{SecureRandom.hex(4)}" }
    requested_at { Time.current }
    request_details { "Please clean the room" }
    status { "pending" }
  end
end
