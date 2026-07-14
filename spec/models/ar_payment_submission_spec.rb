# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPaymentSubmission, type: :model do
  it "requires a slip attachment on create" do
    submission = build(:ar_payment_submission)
    submission.slip = nil

    expect(submission).not_to be_valid
    expect(submission.errors[:slip]).to be_present
  end

  it "rejects a hotel_corporate_account that belongs to a different hotel" do
    other_hotel = create(:hotel)
    submission = build(:ar_payment_submission, hotel: other_hotel)

    expect(submission).not_to be_valid
    expect(submission.errors[:hotel_corporate_account]).to include("must belong to the submission hotel")
  end

  it "approves into a linked ArPayment and stamps the reviewer" do
    submission = create(:ar_payment_submission)
    reviewer = create(:user)
    payment = create(:ar_payment, hotel_corporate_account: submission.hotel_corporate_account)

    submission.approve!(ar_payment: payment, reviewed_by: reviewer)

    expect(submission.reload).to have_attributes(status: "approved", ar_payment: payment, reviewed_by: reviewer)
    expect(submission.reviewed_at).to be_present
  end

  it "rejects with a reason and stamps the reviewer" do
    submission = create(:ar_payment_submission)
    reviewer = create(:user)

    submission.reject!(reason: "Amount does not match slip.", reviewed_by: reviewer)

    expect(submission.reload).to have_attributes(status: "rejected", rejection_reason: "Amount does not match slip.", reviewed_by: reviewer)
  end
end
