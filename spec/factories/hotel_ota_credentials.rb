# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_ota_credential do
    hotel
    sequence(:channel_name) { |n| "Channel #{n}" }
    property_code { "623847" }
    username { "acme-hotel" }
    password { "extranet-secret" }
  end
end
