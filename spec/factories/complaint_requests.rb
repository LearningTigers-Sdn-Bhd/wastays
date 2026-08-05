FactoryBot.define do
  factory :complaint_request do
    booking
    # Letters only, for the same reason as the housekeeping factory: external_id
    # is searched, and a random hex id can contain the digits a spec searches for.
    external_id { "EXT-#{Array.new(8) { ("A".."Z").to_a.sample }.join}" }
    requested_at { Time.current }
    complaint_details { "Water heater not working" }
    status { "pending" }
  end
end
