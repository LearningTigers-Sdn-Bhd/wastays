FactoryBot.define do
  factory :hotel_guest_contact do
    association :hotel
    front_desk_phone { "+60 3 1234 5678" }
    front_desk_email { "frontdesk@example.com" }
    front_desk_open_24h { true }
    emergency_phone { "+60 3 1234 5600" }
    emergency_services_number { "999" }
    escalation_triggers { %w[no_answer guest_asks_for_person] }
    escalation_attempts { 2 }

    trait :with_hours do
      front_desk_open_24h { false }
      front_desk_opens_at { "07:00" }
      front_desk_closes_at { "23:00" }
    end

    trait :overnight do
      front_desk_open_24h { false }
      front_desk_opens_at { "18:00" }
      front_desk_closes_at { "02:00" }
    end
  end
end
