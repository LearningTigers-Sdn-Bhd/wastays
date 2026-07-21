# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPaymentSubmissionAllocation, type: :model do
  it "rejects an amount greater than the invoice's outstanding balance" do
    relationship = create(:hotel_corporate_account)
    invoice = create_open_invoice(relationship: relationship, amount: 50)
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, amount: 999)
    submission.ar_payment_submission_allocations.clear
    allocation = submission.ar_payment_submission_allocations.build(ar_invoice: invoice, amount: 999)

    expect(allocation).not_to be_valid
    expect(allocation.errors[:amount]).to include("cannot exceed the invoice's outstanding balance")
  end

  it "rejects an invoice belonging to a different corporate account" do
    relationship = create(:hotel_corporate_account)
    other_relationship = create(:hotel_corporate_account, hotel: relationship.hotel)
    other_invoice = create_open_invoice(relationship: other_relationship, amount: 50)
    submission = build(:ar_payment_submission, hotel_corporate_account: relationship, amount: 50)
    submission.ar_payment_submission_allocations.clear
    allocation = submission.ar_payment_submission_allocations.build(ar_invoice: other_invoice, amount: 50)

    expect(allocation).not_to be_valid
    expect(allocation.errors[:ar_invoice]).to include("must belong to the same corporate account")
  end

  it "rejects duplicate allocations for the same invoice on one submission" do
    relationship = create(:hotel_corporate_account)
    invoice = create_open_invoice(relationship: relationship, amount: 200)
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, amount: 100)
    submission.ar_payment_submission_allocations.destroy_all
    submission.ar_payment_submission_allocations.create!(ar_invoice: invoice, amount: 100)

    duplicate = submission.ar_payment_submission_allocations.build(ar_invoice: invoice, amount: 50)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:ar_invoice_id]).to be_present
  end

  def create_open_invoice(relationship:, amount:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: "MYR")
  end
end
