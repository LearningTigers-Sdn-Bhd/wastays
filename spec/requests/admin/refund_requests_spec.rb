require "rails_helper"

RSpec.describe "Admin::RefundRequests", type: :request do
  let(:superadmin) { create(:user, :superadmin) }
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) { create(:booking, hotel: hotel, status: "cancelled") }
  let!(:refund_request) { create(:refund_request, booking: booking) }

  before { sign_in_as(superadmin) }

  describe "GET /admin/refund_requests" do
    it "returns http success" do
      get admin_refund_requests_path
      expect(response).to have_http_status(:success)
    end

    it "shows refund requests from all hotels" do
      other_booking = create(:booking, status: "cancelled")
      create(:refund_request, booking: other_booking)
      get admin_refund_requests_path
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(other_booking.confirmation_token)
    end

    it "is inaccessible to non-superadmin" do
      delete logout_path
      get admin_refund_requests_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /admin/refund_requests/:id" do
    it "returns http success" do
      get admin_refund_request_path(refund_request)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /admin/refund_requests/:id/approve" do
    it "sets status to approved" do
      patch approve_admin_refund_request_path(refund_request)
      expect(refund_request.reload.status).to eq("approved")
      expect(response).to redirect_to(admin_refund_request_path(refund_request))
    end

    it "saves optional hotel_note" do
      patch approve_admin_refund_request_path(refund_request), params: { hotel_note: "Will transfer today" }
      expect(refund_request.reload.hotel_note).to eq("Will transfer today")
    end
  end

  describe "PATCH /admin/refund_requests/:id/reject" do
    it "sets status to rejected" do
      patch reject_admin_refund_request_path(refund_request)
      expect(refund_request.reload.status).to eq("rejected")
      expect(response).to redirect_to(admin_refund_request_path(refund_request))
    end

    it "saves optional hotel_note" do
      patch reject_admin_refund_request_path(refund_request), params: { hotel_note: "Does not meet policy" }
      expect(refund_request.reload.hotel_note).to eq("Does not meet policy")
    end
  end

  describe "PATCH /admin/refund_requests/:id/complete" do
    let!(:approved_request) { create(:refund_request, booking: create(:booking, hotel: hotel, status: "cancelled"), status: "approved") }

    it "sets status to completed" do
      patch complete_admin_refund_request_path(approved_request)
      expect(approved_request.reload.status).to eq("completed")
      expect(response).to redirect_to(admin_refund_request_path(approved_request))
    end

    it "sends completed email to guest" do
      expect {
        patch complete_admin_refund_request_path(approved_request)
      }.to have_enqueued_mail(RefundMailer, :completed)
    end

    it "marks the booking payment status as refunded" do
      patch complete_admin_refund_request_path(approved_request)
      expect(approved_request.booking.reload.payment_status).to eq("refunded")
    end

    it "completes without a folio" do
      expect(approved_request.booking.booking_folio).to be_nil

      patch complete_admin_refund_request_path(approved_request)

      expect(approved_request.reload.status).to eq("completed")
      expect(approved_request.booking.reload.payment_status).to eq("refunded")
    end

    it "posts a folio refund when a folio exists" do
      folio = create(:booking_folio, booking: approved_request.booking)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, amount: 200.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 200.0)

      expect {
        patch complete_admin_refund_request_path(approved_request)
      }.to change { folio.folio_transactions.payment.where(category: "refund").count }.by(1)

      refund_transaction = folio.folio_transactions.payment.find_by!(category: "refund")
      expect(refund_transaction.amount).to eq(-approved_request.refund_amount)
      expect(refund_transaction.metadata["refund_request_id"]).to eq(approved_request.id)
      expect(folio.outstanding_balance).to eq(approved_request.refund_amount)
    end

    it "does not duplicate an existing folio refund" do
      folio = create(:booking_folio, booking: approved_request.booking)
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: :payment,
        category: "refund",
        amount: -approved_request.refund_amount,
        metadata: { refund_request_id: approved_request.id }
      )

      expect {
        patch complete_admin_refund_request_path(approved_request)
      }.not_to change { folio.folio_transactions.payment.where(category: "refund").count }
    end

    it "does not complete when folio refund posting fails" do
      create(:booking_folio, booking: approved_request.booking)
      failed_result = OpenStruct.new(success?: false, error: "posting blocked")
      allow(Folios::RecordRefund).to receive(:call).and_return(failed_result)

      expect {
        patch complete_admin_refund_request_path(approved_request)
      }.to raise_error(RuntimeError, /posting blocked/)

      expect(approved_request.reload.status).to eq("approved")
      expect(approved_request.booking.reload.payment_status).not_to eq("refunded")
    end
  end
end
