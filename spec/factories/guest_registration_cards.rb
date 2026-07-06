FactoryBot.define do
  factory :guest_registration_card do
    association :booking
    hotel { booking.hotel }
    status { "draft" }

    trait :signed do
      status { "signed" }
      signer_name { "Jane Guest" }
      signature_data_url { "data:image/png;base64,abc123" }
      signed_at { Time.current }
      terms_snapshot { { "check_in_time" => "3:00 PM", "check_out_time" => "11:00 AM" } }
    end
  end
end
