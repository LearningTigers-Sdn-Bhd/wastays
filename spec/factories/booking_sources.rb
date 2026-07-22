# frozen_string_literal: true

FactoryBot.define do
  factory :booking_source do
    sequence(:key) { |n| "custom_source_#{n}" }
    label { "Custom Source" }
    kind { "ota" }
    icon { "globe" }
    badge_color { "#6B7280" }
    badge_text_color { "#FFFFFF" }
    badge_initial { "C" }
    position { 0 }
    active { true }
  end
end
