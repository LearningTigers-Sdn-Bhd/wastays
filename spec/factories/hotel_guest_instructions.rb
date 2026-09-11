FactoryBot.define do
  factory :hotel_guest_instruction do
    association :hotel
    arrival_instructions { "Please present your booking confirmation at reception." }
    departure_instructions { "Return the room key to reception before leaving." }
  end
end
