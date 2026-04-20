require "rails_helper"

RSpec.describe "HotelPortal::RefundRequests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel, status: "cancelled") }
  let!(:refund_request) { create(:refund_request, booking: booking) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/refund_requests" do
    it "returns http success" do
      get hotel_refund_requests_path(hotel)
      expect(response).to have_http_status(:success)
    end

    it "shows refund requests for this hotel only" do
      other_booking = create(:booking, status: "cancelled")
      create(:refund_request, booking: other_booking)
      get hotel_refund_requests_path(hotel)
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).not_to include(other_booking.confirmation_token)
    end
  end

  describe "GET /hotel/:hotel_id/refund_requests/:id" do
    it "returns http success" do
      get hotel_refund_request_path(hotel, refund_request)
      expect(response).to have_http_status(:success)
    end

    it "returns 404 for refund request from another hotel" do
      other_booking = create(:booking, status: "cancelled")
      other_rr = create(:refund_request, booking: other_booking)
      get hotel_refund_request_path(hotel, other_rr)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /hotel/:hotel_id/refund_requests/:id/approve" do
    it "sets status to approved" do
      patch approve_hotel_refund_request_path(hotel, refund_request)
      expect(refund_request.reload.status).to eq("approved")
      expect(response).to redirect_to(hotel_refund_request_path(hotel, refund_request))
    end

    it "saves optional hotel_note" do
      patch approve_hotel_refund_request_path(hotel, refund_request), params: { hotel_note: "Will transfer today" }
      expect(refund_request.reload.hotel_note).to eq("Will transfer today")
    end
  end

  describe "PATCH /hotel/:hotel_id/refund_requests/:id/reject" do
    it "sets status to rejected" do
      patch reject_hotel_refund_request_path(hotel, refund_request)
      expect(refund_request.reload.status).to eq("rejected")
      expect(response).to redirect_to(hotel_refund_request_path(hotel, refund_request))
    end
  end

  describe "PATCH /hotel/:hotel_id/refund_requests/:id/complete" do
    let!(:approved_request) { create(:refund_request, booking: create(:booking, hotel: hotel, status: "cancelled"), status: "approved") }

    it "sets status to completed" do
      patch complete_hotel_refund_request_path(hotel, approved_request)
      expect(approved_request.reload.status).to eq("completed")
      expect(response).to redirect_to(hotel_refund_request_path(hotel, approved_request))
    end

    it "sends completed email to guest" do
      expect {
        patch complete_hotel_refund_request_path(hotel, approved_request)
      }.to have_enqueued_mail(RefundMailer, :completed)
    end
  end
end
