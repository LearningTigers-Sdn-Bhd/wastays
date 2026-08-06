FactoryBot.define do
  factory :folio_forecasted_charge do
    booking_folio
    stay_date { Date.current }
    charge_kind { "accommodation" }
    identity { "1" }
    amount { 100.0 }
    description { "Room Charge - #{Date.current}" }
    status { "forecast" }
  end
end
