# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ArPaymentSubmissions", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }
  let(:manage_ar_payments) { Permission.find_or_create_by!(slug: "manage_ar_payments") { |permission| permission.name = "Manage AR Payments" } }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent", credit_currency: "MYR") }

  before do
    role.permissions << [ view_reports, manage_ar_payments ]
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "lists only submissions for the current hotel" do
    visible = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-VISIBLE")
    hidden_relationship = create(:hotel_corporate_account, hotel: other_hotel)
    hidden = create(:ar_payment_submission, hotel: other_hotel, hotel_corporate_account: hidden_relationship, reference_number: "SLIP-HIDDEN")

    get hotel_ar_payment_submissions_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("SLIP-VISIBLE")
    expect(response.body).not_to include("SLIP-HIDDEN")
    expect(visible.hotel).to eq(hotel)
    expect(hidden.hotel).to eq(other_hotel)
  end

  it "shows submission details with a link to the slip and the record-payment handoff" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-1", amount: 300)

    get hotel_ar_payment_submission_path(hotel, submission)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("SLIP-1")
    expect(response.body).to include("Record This Payment")
    expect(response.body).to include("View transaction slip")
  end

  it "prefills the AR payment form from a pending submission" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-PREFILL", amount: 275, payment_method: "bank_transfer")

    get new_hotel_ar_payment_path(hotel, hotel_corporate_account_id: relationship.id, ar_payment_submission_id: submission.id)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("SLIP-PREFILL")
    expect(response.body).to include('value="275.0"')
    expect(response.body).to include("submitted payment slip")
  end

  it "approving the prefilled payment marks the submission approved and links the real ArPayment" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-APPROVE", amount: 150, currency: "MYR")

    expect {
      post hotel_ar_payments_path(hotel), params: {
        ar_payment_submission_id: submission.id,
        ar_payment: {
          hotel_corporate_account_id: relationship.id,
          reference_number: submission.reference_number,
          amount: submission.amount,
          currency: submission.currency,
          received_at: submission.received_at,
          payment_method: submission.payment_method
        }
      }
    }.to change(ArPayment, :count).by(1)

    submission.reload
    expect(submission.status).to eq("approved")
    expect(submission.ar_payment).to eq(ArPayment.last)
    expect(submission.reviewed_by).to eq(user)
    expect(response).to redirect_to(hotel_ar_payment_path(hotel, ArPayment.last))
  end

  it "rejects a submission with a reason" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship)

    patch reject_hotel_ar_payment_submission_path(hotel, submission), params: { rejection_reason: "Slip amount mismatch" }

    expect(submission.reload).to have_attributes(status: "rejected", rejection_reason: "Slip amount mismatch", reviewed_by: user)
    expect(response).to redirect_to(hotel_ar_payment_submissions_path(hotel))
  end

  it "requires manage_ar_payments permission" do
    role.permissions.delete(manage_ar_payments)
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship)

    get hotel_ar_payment_submissions_path(hotel)
    expect(flash[:alert]).to include("not authorized")

    get hotel_ar_payment_submission_path(hotel, submission)
    expect(flash[:alert]).to include("not authorized")
  end
end
