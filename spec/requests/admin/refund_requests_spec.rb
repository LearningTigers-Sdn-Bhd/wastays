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
  end
end
