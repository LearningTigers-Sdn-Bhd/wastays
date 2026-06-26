# frozen_string_literal: true

FactoryBot.define do
  factory :folio_operation_log do
    association :booking
    hotel { booking.hotel }
    actor { association(:user) }
    operation_type { "create_folio" }
    metadata { {} }
  end
end
