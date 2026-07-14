# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::ArPaymentSubmissions", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account, account_type: "travel_agent") }

  before do
    sign_in_as(user)
    user.account.hotel_corporate_accounts.reload
  end

  it "shows the submission's own detail page with a link to the uploaded slip and its invoices" do
    submission = create(:ar_payment_submission, hotel_corporate_account: relationship, reference_number: "SLIP-DETAIL", amount: 320)

    get corporate_ar_payment_submission_path(submission)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("SLIP-DETAIL")
    expect(response.body).to include("View transaction slip")
    expect(response.body).to include(submission.ar_invoices.first.formatted_invoice_number)
  end

  it "does not allow viewing a submission belonging to another corporate account" do
    other_relationship = create(:hotel_corporate_account)
    hidden = create(:ar_payment_submission, hotel_corporate_account: other_relationship)

    get corporate_ar_payment_submission_path(hidden)

    expect(response).to have_http_status(:not_found)
  end

  it "shows the outstanding invoice(s) requested on the new submission form" do
    invoice = create_open_invoice(relationship: relationship, amount: 275)

    get new_corporate_ar_payment_submission_path(ar_invoice_id: invoice.id)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(invoice.formatted_invoice_number)
    expect(response.body).to include("275.00")
  end

  it "submits a payment targeting a single outstanding invoice, with an attached slip" do
    invoice = create_open_invoice(relationship: relationship, amount: 450)

    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          ar_invoice_ids: [ invoice.id ],
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
      reference_number: "BANK-REF-1",
      amount: 450.to_d
    )
    expect(submission.ar_invoices).to contain_exactly(invoice)
    expect(submission.slip).to be_attached
    expect(response).to redirect_to(corporate_ar_payments_path)
  end

  it "submits one bank transfer covering multiple outstanding invoices" do
    invoice1 = create_open_invoice(relationship: relationship, amount: 200)
    invoice2 = create_open_invoice(relationship: relationship, amount: 300)

    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          ar_invoice_ids: [ invoice1.id, invoice2.id ],
          reference_number: "BANK-REF-MULTI",
          received_at: Date.current,
          payment_method: "bank_transfer",
          slip: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
        }
      }
    }.to change(ArPaymentSubmission, :count).by(1)

    submission = ArPaymentSubmission.last
    expect(submission.amount).to eq(500.to_d)
    expect(submission.ar_invoices).to contain_exactly(invoice1, invoice2)
  end

  it "rejects a submission without a target invoice" do
    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          reference_number: "BANK-REF-2",
          received_at: Date.current,
          payment_method: "bank_transfer",
          slip: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
        }
      }
    }.not_to change(ArPaymentSubmission, :count)

    expect(response).to redirect_to(pay_invoices_corporate_ar_payments_path)
  end

  it "rejects a submission targeting an invoice from a corporate account the agent doesn't belong to" do
    other_relationship = create(:hotel_corporate_account)
    other_invoice = create_open_invoice(relationship: other_relationship, amount: 100)

    expect {
      post corporate_ar_payment_submissions_path, params: {
        ar_payment_submission: {
          ar_invoice_ids: [ other_invoice.id ],
          reference_number: "BANK-REF-2",
          received_at: Date.current,
          payment_method: "bank_transfer",
          slip: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
        }
      }
    }.not_to change(ArPaymentSubmission, :count)

    expect(response).to redirect_to(pay_invoices_corporate_ar_payments_path)
  end

  def create_open_invoice(relationship:, amount:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: "MYR")
  end
end
