require "rails_helper"

RSpec.describe "Guest::Bookings invoice", type: :request do
  let(:guest) do
    create(:guest,
      name: "Invoice Guest",
      email: "invoice.guest@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      document_type: "passport",
      government_id: "A1234567"
    )
  end
  let(:other_guest) do
    create(:guest,
      name: "Other",
      email: "other@example.com",
      phone: "+60199999999",
      country: "Malaysia",
      document_type: "passport",
      government_id: "B1234567"
    )
  end
  let(:hotel) { create(:hotel, status: "approved") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard Room") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Invoice Guest",
      guest_email: "invoice.guest@example.com",
      guest_phone: "+60123456789",
      total_amount: 300.0,
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
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Standard Room" }
    )
  end

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    sign_in_guest!(guest)
  end

  def create_closed_folio_with_charge!(target_booking)
    folio = create(:booking_folio, booking: target_booking, hotel: target_booking.hotel, status: "closed", invoice_number: 123)
    code = create(:transaction_code, hotel: target_booking.hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation")
    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 300,
      description: "Room Charge - Standard Room")
    create(:folio_invoice, booking_folio: folio)
    folio
  end

  def sign_in_guest!(g)
    otp = g.generate_otp!
    post guest_login_path, params: { phone: g.phone, otp: otp }
    follow_redirect!
  end

  describe "GET /guest/bookings/:id/invoice" do
    it "returns a PDF for the guest's own booking" do
      create_closed_folio_with_charge!(booking)

      get invoice_guest_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "redirects when the booking has no closed folio" do
      get invoice_guest_booking_path(booking)

      expect(response).to redirect_to(guest_bookings_path)
      expect(flash[:alert]).to eq("No finalized guest invoice is available for this booking.")
    end

    it "redirects when the booking belongs to another guest" do
      other_booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: other_booking, room_type: room_type, subtotal: 100.0)
      create(:booking_guest, guest: other_guest, booking: other_booking, is_primary: true)

      get invoice_guest_booking_path(other_booking)

      expect(response).to redirect_to(guest_bookings_path)
    end

    it "redirects when not logged in" do
      delete guest_logout_path
      get invoice_guest_booking_path(booking)

      expect(response).to redirect_to(guest_login_path)
    end
  end
end
