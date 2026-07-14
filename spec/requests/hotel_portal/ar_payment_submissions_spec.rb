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

  it "prefills the allocation for the submission's target invoice without needing ar_invoice_id in the URL" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-TARGETED", amount: 275)
    invoice = submission.ar_invoices.first

    get new_hotel_ar_payment_path(hotel, hotel_corporate_account_id: relationship.id, ar_payment_submission_id: submission.id)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(invoice.formatted_invoice_number)
    expect(response.body).to include("targeting invoice #{invoice.formatted_invoice_number}")
    expect(response.body).to include("name=\"allocations[#{invoice.id}]\"")
    expect(response.body).to include('value="275.0"')
  end

  it "prefills allocations for every invoice a multi-invoice submission targets" do
    booking1 = create(:booking, hotel: hotel)
    folio1 = create(:booking_folio, :secondary, booking: booking1, hotel: hotel, hotel_corporate_account: relationship)
    invoice1 = create(:ar_invoice, hotel: hotel, booking_folio: folio1, hotel_corporate_account: relationship, amount: 100, paid_amount: 0, outstanding_amount: 100, currency: "MYR")
    booking2 = create(:booking, hotel: hotel)
    folio2 = create(:booking_folio, :secondary, booking: booking2, hotel: hotel, hotel_corporate_account: relationship)
    invoice2 = create(:ar_invoice, hotel: hotel, booking_folio: folio2, hotel_corporate_account: relationship, amount: 150, paid_amount: 0, outstanding_amount: 150, currency: "MYR")

    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, amount: 100, reference_number: "SLIP-MULTI")
    submission.ar_payment_submission_allocations.destroy_all
    submission.ar_payment_submission_allocations.create!(ar_invoice: invoice1, amount: 100)
    submission.ar_payment_submission_allocations.create!(ar_invoice: invoice2, amount: 150)
    submission.update!(amount: 250)

    get new_hotel_ar_payment_path(hotel, hotel_corporate_account_id: relationship.id, ar_payment_submission_id: submission.id)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("targeting invoices #{invoice1.formatted_invoice_number} and #{invoice2.formatted_invoice_number}")
    expect(response.body).to include("name=\"allocations[#{invoice1.id}]\"")
    expect(response.body).to include("name=\"allocations[#{invoice2.id}]\"")
    expect(response.body).to include('value="100.0"')
    expect(response.body).to include('value="150.0"')
  end

  it "renders agent-submitted fields as read-only, not editable inputs" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-READONLY", amount: 275, payment_method: "bank_transfer")

    get new_hotel_ar_payment_path(hotel, hotel_corporate_account_id: relationship.id, ar_payment_submission_id: submission.id)

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('type="text" name="ar_payment[reference_number]"')
    expect(response.body).not_to include('type="number" name="ar_payment[amount]"')
    expect(response.body).to include('type="hidden" name="ar_payment[reference_number]"')
    expect(response.body).to include('type="hidden" name="ar_payment[amount]"')
    expect(response.body).to include('type="hidden" name="ar_payment[payment_method]"')
    expect(response.body).to include("can't be edited here")
  end

  it "offers a reject-with-remarks form directly on the review page" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-REVIEW-REJECT")

    get new_hotel_ar_payment_path(hotel, hotel_corporate_account_id: relationship.id, ar_payment_submission_id: submission.id)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(reject_hotel_ar_payment_submission_path(hotel, submission))
    expect(response.body).to include("rejection_reason")
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
    expect(response).to redirect_to(hotel_ar_payments_path(hotel))
  end

  it "requires a rejection reason and re-shows the submission with an alert" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship)

    patch reject_hotel_ar_payment_submission_path(hotel, submission), params: { rejection_reason: "" }

    expect(submission.reload.status).to eq("pending")
    expect(response).to redirect_to(hotel_ar_payment_submission_path(hotel, submission))
    expect(flash[:alert]).to include("Rejection reason can't be blank")
  end

  it "requires manage_ar_payments permission" do
    role.permissions.delete(manage_ar_payments)
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship)

    get hotel_ar_payment_submission_path(hotel, submission)
    expect(flash[:alert]).to include("not authorized")
  end
end
