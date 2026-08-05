# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_reservation_policy do
    hotel
    policy_type { "late_checkout" }
    active { true }
    pricing_type { "manual" }
    allow_amount_override { true }
    position { 1 }

    # Falls back to the late-checkout code for an unrecognised policy_type so that
    # validation specs can build an invalid type without the factory raising first.
    transaction_code do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      system_key = {
        "late_checkout" => "late_checkout_revenue",
        "early_departure" => "early_departure_revenue",
        "no_show" => "no_show_revenue",
        "cancellation" => "cancel_revenue"
      }.fetch(policy_type, "late_checkout_revenue")
      hotel.transaction_codes.find_by(system_key: system_key)
    end

    trait :no_show do
      policy_type { "no_show" }
      pricing_type { "nights" }
      rate_value { 1 }
      allow_amount_override { false }
    end

    trait :cancellation do
      policy_type { "cancellation" }
      active { false }
    end

    trait :charging_cancellation do
      cancellation
      active { true }
      refund_processing_days { 7 }
      refund_method { "original_payment_method" }
    end
  end

  factory :hotel_cancellation_policy_tier do
    association :hotel_reservation_policy, factory: %i[hotel_reservation_policy charging_cancellation]
    days_before_arrival { 14 }
    pricing_type { "percentage" }
    percentage_basis { "total_stay" }
    rate_value { 0 }
    position { 1 }
  end
end
