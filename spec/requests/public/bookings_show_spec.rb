# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Bookings", type: :request do
  let(:hotel) { create(:hotel, name: "Luxury Resort", city: "Malacca", country: "Malaysia") }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:booking) do
    create(:booking,
           hotel: hotel,
           guest_name: "John Doe",
           guest_email: "john@example.com",
           guest_phone: "+60123456789",
           check_in: Date.current,
           check_out: Date.current + 2.days,
           total_amount: 500.0,
           confirmation_token: "CONF123")
  end

  describe "GET /public/bookings/:id" do
    it "renders the booking show page with correct details" do
      get booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking Secured")
      expect(response.body).to include("CONF123")
      expect(response.body).to include("Luxury Resort")
      expect(response.body).to include("John Doe")
      expect(response.body).to include("RM 500.00")
      expect(response.body).to include("2 Nights")
    end

    it "shows e-invoice download when ready" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        status: "valid",
        internal_id: "SAH-300000001",
        uuid: "26ZBY0Y5YVQX868FNJRC",
        submission_uid: "4MCJS3QHYW358H8CNJRC",
        long_id: "T19FQ4RT6FJDCBSENJRCRPVK10IW8KKW1782101467",
        submitted_at: Time.current,
        validated_at: Time.current
      )

      get booking_path(booking.confirmation_token)

      expect(response.body).to include("Download E-Invoice")
    end

    it "shows e-invoice request button when payment concluded and still within request window" do
      booking.update!(payment_status: "captured")
      create(:payment_transaction, booking: booking, status: "captured",
        gateway: "stripe", captured_at: Time.current, amount_subunits: 50_000, currency: "MYR")

      get booking_path(booking.confirmation_token)

      expect(response.body).to include("Request E-Invoice")
    end

    it "shows e-invoice failure message when submission is rejected" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        status: "invalid",
        document_scenario: "guest_invoice",
        document_type: "01",
        error_details: { message: "Booking guest city must map to a valid Malaysia state code" })

      get booking_path(booking.confirmation_token)

      expect(response.body).to include("E-Invoice Submission Failed")
      expect(response.body).to include("Booking guest city must map to a valid Malaysia state code")
    end
  end
end
