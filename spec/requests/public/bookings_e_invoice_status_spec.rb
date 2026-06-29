require "rails_helper"

RSpec.describe "Public booking e-invoice status", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      confirmation_token: "WS-EINVSTAT1",
      guest_name: "John Doe",
      guest_email: "john@example.com",
      guest_phone: "+60111234567",
      payment_status: "captured",
      total_amount: 200.0,
      currency: "MYR",
      check_in: Date.current,
      check_out: Date.current + 2.days)
  end

  it "returns ready payload with adjustment-note download url" do
    create(:payment_transaction, booking: booking, status: "captured",
      gateway: "stripe", captured_at: Time.current, amount_subunits: 20_000, currency: "MYR")
    create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      document_scenario: "guest_invoice",
      document_type: "03",
      status: "valid")

    get status_e_invoice_booking_path(booking.confirmation_token), as: :json

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("ready")
    expect(json["document_label"]).to eq("Debit Note")
    expect(json["download_url"]).to eq(e_invoice_booking_path(booking.confirmation_token))
  end
end
