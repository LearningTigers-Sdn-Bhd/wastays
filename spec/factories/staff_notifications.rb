FactoryBot.define do
  factory :staff_notification do
    association :subject, factory: :night_audit
    hotel { subject.hotel }
    association :recipient, factory: :user
    notification_type { "night_audit_action_required" }
    severity { "warning" }
    title { "Night Audit needs attention" }
    message { "The business date did not change." }
    sequence(:deduplication_key) { |number| "staff-notification-#{number}" }
  end
end
