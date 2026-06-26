# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_transaction_configuration do
    association :hotel
    room_revenue_tax_rule_application { "new_bookings_only" }
  end
end
