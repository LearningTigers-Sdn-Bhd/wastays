# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_submission do
    hotel
    submitted_by { association :user, account: hotel.account }
    sequence(:idempotency_key) { |number| "submission-#{number}" }
    status { "pending_review" }
    snapshot_version { OnboardingSubmission::SNAPSHOT_VERSION }
    snapshot { { "hotel" => { "name" => hotel.name } } }
    readiness_snapshot { { "ready" => true, "blocking_issues" => [], "warnings" => [] } }
    configuration_digest { Digest::SHA256.hexdigest(snapshot.to_json) }
    submitted_at { Time.current }
  end

  factory :onboarding_delivery do
    onboarding_submission
    delivery_type { "admin_submitted" }
    sequence(:idempotency_key) { |number| "delivery-#{number}" }
    status { "pending" }
    recipient_email { "admin@example.com" }
  end
end
