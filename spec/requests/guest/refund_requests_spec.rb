require "rails_helper"

RSpec.describe "Guest::RefundRequests", type: :request do
  let(:guest) do
    create(
      :guest,
      name: "Refund Guest",
      email: "refund.guest@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      document_type: "passport",
      government_id: "A1234567"
    )
  end
  let(:booking) { create(:booking, status: "confirmed", check_in: Date.current + 10.days) }

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)
    sign_in_guest!(guest)
  end

  def sign_in_guest!(guest)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
    expect(response).to redirect_to(guest_dashboard_path)
  end

  describe "GET /guest/bookings/:booking_id/refund_requests/new" do
    it "returns http success for an eligible booking" do
      get new_guest_booking_refund_request_path(booking)
      expect(response).to have_http_status(:success)
    end

    it "redirects when booking is not the guest's" do
      other_booking = create(:booking, status: "confirmed")
      get new_guest_booking_refund_request_path(other_booking)
      expect(response).to redirect_to(guest_bookings_path)
    end
  end

  describe "GET /guest/refund_requests" do
    it "shows only submitted refund requests" do
      refund_booking = create(:booking, status: "cancelled", check_in: Date.current + 5.days)
      create(:booking_guest, guest: guest, booking: refund_booking, is_primary: true)
      create(:refund_request, booking: refund_booking, status: "pending")

      no_refund_booking = create(:booking, status: "confirmed", check_in: Date.current + 10.days)
      create(:booking_guest, guest: guest, booking: no_refund_booking, is_primary: true)

      get guest_refund_requests_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(refund_booking.confirmation_token)
      expect(response.body).not_to include(no_refund_booking.confirmation_token)
      expect(response.body).to include("Pending")
    end
  end

  describe "GET /guest/refund_requests/:id" do
    it "shows refund details for own refund request" do
      refund = create(:refund_request, booking: booking, status: "pending")

      get guest_refund_request_path(refund)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Refund Details")
      expect(response.body).to include(booking.confirmation_token)
    end

    it "shows a warm message based on refund status" do
      expected_message_by_status = {
        "pending" => "Thanks for your patience. We have received your refund request and our team is reviewing it now.",
        "approved" => "Good news. Your refund request has been approved and we are preparing the payout.",
        "completed" => "Your refund is complete. The amount has been processed to your bank account.",
        "rejected" => "We are sorry. Your refund request could not be approved this time. Please check the hotel note for details."
      }

      expected_message_by_status.each do |status, expected_message|
        refund = create(:refund_request, booking: booking, status: status)

        get guest_refund_request_path(refund)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Refund Status")
        expect(response.body).to include("Status")
        expect(response.body).to include(status.humanize)
        expect(response.body).to include(expected_message)

        refund.destroy!
      end
    end

    it "redirects when refund request does not belong to guest" do
      other_booking = create(:booking, status: "cancelled", check_in: Date.current + 7.days)
      other_refund = create(:refund_request, booking: other_booking, status: "pending")

      get guest_refund_request_path(other_refund)

      expect(response).to redirect_to(guest_refund_requests_path)
    end
  end

  describe "POST /guest/bookings/:booking_id/refund_requests" do
    let(:valid_params) do
      {
        refund_request: {
          reason: "Change of plans",
          bank_name: "Maybank",
          account_holder_name: "Ahmad Ali",
          account_number: "1234567890",
          account_type: "savings"
        }
      }
    end

    it "cancels the booking and creates a refund request" do
      expect {
        post guest_booking_refund_requests_path(booking), params: valid_params
      }.to change(RefundRequest, :count).by(1)

      expect(booking.reload.status).to eq("cancelled")
      expect(response).to redirect_to(guest_booking_path(booking))
    end

    it "redirects back to bookings list when submitted from list flow" do
      expect {
        post guest_booking_refund_requests_path(booking), params: valid_params.merge(return_to: "list")
      }.to change(RefundRequest, :count).by(1)

      expect(response).to redirect_to(guest_bookings_path)
    end

    it "redirects back to booking details when submitted from details flow" do
      expect {
        post guest_booking_refund_requests_path(booking), params: valid_params.merge(return_to: "details")
      }.to change(RefundRequest, :count).by(1)

      expect(response).to redirect_to(guest_booking_path(booking))
    end

    it "redirects with alert when policy eligibility fails" do
      close_booking = create(:booking, status: "confirmed", check_in: Date.current + 1.day)
      create(:booking_guest, guest: guest, booking: close_booking, is_primary: true)

      post guest_booking_refund_requests_path(close_booking), params: valid_params
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("too close to check-in")
    end

    it "renders with alert when required params are missing" do
      post guest_booking_refund_requests_path(booking), params: { refund_request: { reason: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please complete your bank details")
    end

    it "redirects to guest login when not authenticated" do
      delete guest_logout_path
      post guest_booking_refund_requests_path(booking), params: valid_params
      expect(response).to redirect_to(guest_login_path)
    end
  end
end
