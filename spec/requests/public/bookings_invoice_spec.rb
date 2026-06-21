require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe "Public::Bookings invoice", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard Room") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      confirmation_token: "WS-INVTEST1",
      guest_name: "John Doe",
      guest_email: "john@example.com",
      guest_phone: "+60111234567",
      total_amount: 200.0,
      currency: "MYR",
      payment_status: "captured",
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0,
      check_in: Date.current,
      check_out: Date.current + 2.days
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      quantity: 1,
      subtotal: 200.0,
      room_type_snapshot: { "name" => "Standard Room" }
    )
  end

  describe "GET /bookings/:id/invoice" do
    it "returns a PDF for a valid confirmation token" do
      get invoice_booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline")
      expect(response.headers["Content-Disposition"]).to include("wastays-invoice-WS-INVTEST1.pdf")
    end

    it "uses the redesigned guest folio invoice when the booking has a folio" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "closed", invoice_number: 123)
      code = create(:transaction_code, hotel: hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation")
      create(:folio_transaction,
        booking_folio: folio,
        transaction_code: code,
        transaction_type: "charge",
        category: "accommodation",
        amount: 200,
        description: "Room Charge - Standard Room")

      get invoice_booking_path(booking.confirmation_token)

      text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(text).to include("GUEST FOLIO / INVOICE")
      expect(text).to include("Room Charge - Standard Room")
      expect(text).to include("SUMMARY (MYR)")
    end

    it "returns 404 for an unknown token" do
      get invoice_booking_path("WS-DOESNOTEXIST")

      expect(response).to have_http_status(:not_found)
    end
  end
end
