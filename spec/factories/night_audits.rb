FactoryBot.define do
  factory :night_audit do
    association :hotel
    association :performed_by_user, factory: :user
    business_date { Date.current }
    status { "completed" }
    trigger_mode { "manual" }
    started_at { Time.current }
    completed_at { Time.current }
    summary { {} }
    blocked_details { {} }
    exceptions { {} }
    force_closed { false }
  end
end
