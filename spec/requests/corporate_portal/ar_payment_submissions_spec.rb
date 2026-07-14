# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArPaymentSubmissions", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account, account_type: "travel_agent") }

  before do
    sign_in_as(user)
    user.account.hotel_corporate_accounts.reload
  end

  it "lists only submissions belonging to the current corporate account" do
    relationship
    visible = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-VISIBLE")
    hidden_relationship = create(:hotel_corporate_account)
    hidden = create(:ar_payment_submission, hotel_corporate_account: hidden_relationship, reference_number: "SLIP-HIDDEN")

    get corporate_ar_payment_submissions_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("SLIP-VISIBLE")
    expect(response.body).not_to include("SLIP-HIDDEN")
    expect(visible.hotel_corporate_account).to eq(relationship)
    expect(hidden.hotel_corporate_account).to eq(hidden_relationship)
  end

  it "submits a payment with an attached slip" do
    relationship

    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          hotel_corporate_account_id: relationship.id,
          amount: "450.00",
          currency: "MYR",
          reference_number: "BANK-REF-1",
          received_at: Date.current,
          payment_method: "bank_transfer",
          slip: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
        }
      }
    }.to change(ArPaymentSubmission, :count).by(1)

    submission = ArPaymentSubmission.last
    expect(submission).to have_attributes(
      hotel_corporate_account: relationship,
      submitted_by: user,
      status: "pending",
      reference_number: "BANK-REF-1"
    )
    expect(submission.slip).to be_attached
    expect(response).to redirect_to(corporate_ar_payment_submissions_path)
  end

  it "rejects a submission for a hotel the corporate account is not linked to" do
    other_relationship = create(:hotel_corporate_account)

    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          hotel_corporate_account_id: other_relationship.id,
          amount: "100.00",
          currency: "MYR",
          reference_number: "BANK-REF-2",
          received_at: Date.current,
          payment_method: "bank_transfer",
          slip: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
        }
      }
    }.not_to change(ArPaymentSubmission, :count)

    expect(response).to redirect_to(new_corporate_ar_payment_submission_path)
  end
end
