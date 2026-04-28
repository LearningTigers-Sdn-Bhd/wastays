# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint do
    name { "Test Webhook" }
    url { "https://example.com/webhook" }
    enabled { true }
  end
end
