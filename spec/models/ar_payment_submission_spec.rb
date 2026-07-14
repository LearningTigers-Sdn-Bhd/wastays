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

  it "requires at least one target invoice on create" do
    submission = build(:ar_payment_submission)
    submission.ar_payment_submission_allocations.clear

    expect(submission).not_to be_valid
    expect(submission.errors[:base]).to include("must target at least one outstanding invoice")
  end

  it "allows an already-persisted submission without allocations to still be approved/rejected" do
    submission = create(:ar_payment_submission)
    submission.ar_payment_submission_allocations.destroy_all
    reviewer = create(:user)

    expect(submission.reload.reject!(reason: "No matching invoice", reviewed_by: reviewer)).to eq(true)
  end

  it "requires the amount to equal the sum of allocated invoice amounts" do
    relationship = create(:hotel_corporate_account)
    invoice = create_open_invoice(relationship: relationship, amount: 500)
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, amount: 999)
    submission.ar_payment_submission_allocations.clear
    submission.ar_payment_submission_allocations.build(ar_invoice: invoice, amount: 500)

    expect(submission).not_to be_valid
    expect(submission.errors[:amount]).to include("must equal the sum of the allocated invoice amounts")
  end

  it "supports one submission targeting multiple invoices" do
    relationship = create(:hotel_corporate_account)
    invoice1 = create_open_invoice(relationship: relationship, amount: 200)
    invoice2 = create_open_invoice(relationship: relationship, amount: 300)
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, amount: 500)
    submission.ar_payment_submission_allocations.clear
    submission.ar_payment_submission_allocations.build(ar_invoice: invoice1, amount: 200)
    submission.ar_payment_submission_allocations.build(ar_invoice: invoice2, amount: 300)

    expect(submission).to be_valid
    expect(submission.ar_payment_submission_allocations.map(&:ar_invoice)).to contain_exactly(invoice1, invoice2)
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

  def create_open_invoice(relationship:, amount:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: "MYR")
  end
end
