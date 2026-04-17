FactoryBot.define do
  factory :payment_transaction do
    association :booking_quote
    gateway { "razorpay" }
    external_reference { "pay_#{SecureRandom.hex(6)}" }
    gateway_order_id { "order_#{SecureRandom.hex(6)}" }
    status { "captured" }
    payment_method { "netbanking" }
    amount_subunits { 20000 }
    currency { "MYR" }
    event_source { "client_callback" }
    metadata { {} }
    gateway_payload { {} }
  end
end
