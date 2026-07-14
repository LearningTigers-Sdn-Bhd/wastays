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

  it "requires a target invoice on create" do
    submission = build(:ar_payment_submission, ar_invoice: nil)

    expect(submission).not_to be_valid
    expect(submission.errors[:ar_invoice]).to be_present
  end

  it "allows an already-persisted submission without a target invoice to still be approved/rejected" do
    relationship = create(:hotel_corporate_account)
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship)
    submission.update_column(:ar_invoice_id, nil)
    reviewer = create(:user)

    expect(submission.reload.reject!(reason: "No matching invoice", reviewed_by: reviewer)).to eq(true)
  end

  it "rejects an invoice belonging to a different corporate account" do
    relationship = create(:hotel_corporate_account)
    other_relationship = create(:hotel_corporate_account, hotel: relationship.hotel)
    other_invoice = create(:ar_invoice, hotel: relationship.hotel, hotel_corporate_account: other_relationship,
      booking_folio: create(:booking_folio, :secondary, booking: create(:booking, hotel: relationship.hotel), hotel: relationship.hotel, hotel_corporate_account: other_relationship))
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, ar_invoice: other_invoice, amount: 50)

    expect(submission).not_to be_valid
    expect(submission.errors[:ar_invoice]).to include("must belong to the same corporate account")
  end

  it "rejects an amount greater than the invoice's outstanding balance" do
    relationship = create(:hotel_corporate_account)
    invoice = create(:ar_invoice, hotel: relationship.hotel, hotel_corporate_account: relationship, amount: 50, paid_amount: 0, outstanding_amount: 50,
      booking_folio: create(:booking_folio, :secondary, booking: create(:booking, hotel: relationship.hotel), hotel: relationship.hotel, hotel_corporate_account: relationship))
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, ar_invoice: invoice, amount: 999)

    expect(submission).not_to be_valid
    expect(submission.errors[:amount]).to include("cannot exceed the invoice's outstanding balance")
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

  it "requires a rejection reason before it can be rejected" do
    submission = create(:ar_payment_submission)
    reviewer = create(:user)

    result = submission.reject!(reason: "", reviewed_by: reviewer)

    expect(result).to eq(false)
    expect(submission.reload.status).to eq("pending")
  end
end
