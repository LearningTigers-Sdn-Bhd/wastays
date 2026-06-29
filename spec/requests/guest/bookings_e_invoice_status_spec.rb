require "rails_helper"

RSpec.describe "Guest booking e-invoice status", type: :request do
  let(:guest) do
    create(:guest,
      name: "Invoice Guest",
      email: "invoice.guest@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      document_type: "ic",
      government_id: "820916125537")
  end
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: guest.name,
      guest_email: guest.email,
      guest_phone: guest.phone,
      payment_status: "captured",
      total_amount: 300.0,
      currency: "MYR",
      check_in: Date.current,
      check_out: Date.current + 2.days)
  end

  before do
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
    follow_redirect!
  end

  it "returns failed payload when latest guest-facing submission is invalid" do
    create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      document_scenario: "guest_invoice",
      document_type: "01",
      status: "invalid",
      consolidated: false,
      error_details: { message: "TIN mismatch" })

    get status_e_invoice_guest_booking_path(booking), as: :json

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("failed")
    expect(json["message"]).to include("TIN mismatch")
  end
end
