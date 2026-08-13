require "rails_helper"

RSpec.describe Onboarding::DeliverJob, type: :job do
  let(:hotel) { create(:hotel) }
  let(:submitter) { create(:user, account: hotel.account) }
  let(:submission) { create(:onboarding_submission, hotel:, submitted_by: submitter) }

  it "creates a held staff invitation without sending email" do
    HotelOps::SeedAccountRoles.call(hotel.account)
    role = hotel.account.roles.find_by!(slug: "front_desk")
    draft = create(:onboarding_staff_draft, hotel:, role:, send_invitation: false)
    delivery = create(
      :onboarding_delivery, onboarding_submission: submission,
      delivery_type: "staff_invitation", source_type: "OnboardingStaffDraft", source_id: draft.id,
      recipient_email: nil
    )

    expect {
      described_class.perform_now(delivery.id)
    }.not_to change { ActionMailer::Base.deliveries.size }

    expect(delivery.reload).to have_attributes(status: "held", attempt_count: 1, completed_at: be_present)
    expect(draft.reload.invitation).to be_present
    expect(draft.invitation.last_sent_at).to be_nil
  end

  it "delivers a lifecycle email and does not repeat completed work" do
    delivery = create(
      :onboarding_delivery, onboarding_submission: submission,
      delivery_type: "admin_submitted", recipient_email: "reviewer@example.com"
    )

    expect {
      described_class.perform_now(delivery.id)
      described_class.perform_now(delivery.id)
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(delivery.reload).to have_attributes(status: "sent", attempt_count: 1, completed_at: be_present)
  end
end
