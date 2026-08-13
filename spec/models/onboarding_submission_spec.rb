require "rails_helper"

RSpec.describe OnboardingSubmission, type: :model do
  it "allows only one pending submission per hotel" do
    submission = create(:onboarding_submission)

    expect {
      create(:onboarding_submission, hotel: submission.hotel, submitted_by: submission.submitted_by)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "keeps reviewed history after a new submission" do
    first = create(
      :onboarding_submission, status: "changes_requested", reviewed_by: create(:user, :superadmin),
      reviewed_at: Time.current, review_explanation: "Update the room details."
    )

    expect {
      create(:onboarding_submission, hotel: first.hotel, submitted_by: first.submitted_by)
    }.to change(first.hotel.onboarding_submissions, :count).by(1)
  end

  it "does not allow the submitted snapshot to be replaced" do
    submission = create(:onboarding_submission)

    expect {
      submission.update!(snapshot: { "tampered" => true }, configuration_digest: "replacement")
    }.to raise_error(ActiveRecord::ReadonlyAttributeError)

    expect(submission.reload.snapshot).not_to include("tampered")
  end
end
