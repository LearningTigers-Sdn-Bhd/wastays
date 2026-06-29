require "rails_helper"

RSpec.describe "Guest::Bookings e-invoice", type: :request do
  let(:guest) do
    create(:guest,
      name: "Invoice Guest",
      email: "invoice.guest@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      document_type: "ic",
      government_id: "820916125537"
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
      guest_document_type: "ic",
      guest_government_id: "820916125537",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_country: "Malaysia",
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
      quantity: 1,
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Standard Room" }
    )
  end

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
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
    sign_in_guest!(guest)
  end

  def sign_in_guest!(current)
    otp = current.generate_otp!
    post guest_login_path, params: { phone: current.phone, otp: otp }
    follow_redirect!
  end

  describe "GET /guest/bookings/:id/e_invoice" do
    it "returns a PDF for guest own booking" do
      get e_invoice_guest_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "returns a specific original e-invoice when submission_id is given" do
      original = booking.e_invoice_submissions.find_by!(internal_id: "SAH-300000001")
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "03",
        status: "valid",
        internal_id: "SAH-300000001-DN",
        uuid: "DN26ZBY0Y5YVQX868FNJRC",
        submission_uid: "DN4MCJS3QHYW358H8CNJRC",
        long_id: "DNT19FQ4RT6FJDCBSENJRCRPVK10IW8KKW1782101467",
        submitted_at: 1.minute.from_now,
        validated_at: 1.minute.from_now)

      get e_invoice_guest_booking_path(booking, submission_id: original.id)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("wastays-e-invoice-SAH-300000001.pdf")
    end

    it "redirects when booking belongs to another guest" do
      other_booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: other_booking, room_type: room_type, subtotal: 100.0)
      create(:booking_guest, guest: other_guest, booking: other_booking, is_primary: true)

      get e_invoice_guest_booking_path(other_booking)

      expect(response).to redirect_to(guest_bookings_path)
    end

    it "redirects when not logged in" do
      delete guest_logout_path

      get e_invoice_guest_booking_path(booking)

      expect(response).to redirect_to(guest_login_path)
    end

    it "downloads the latest adjustment note when one exists" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "03",
        status: "valid",
        internal_id: "SAH-300000001-DN",
        uuid: "DN26ZBY0Y5YVQX868FNJRC",
        submission_uid: "DN4MCJS3QHYW358H8CNJRC",
        long_id: "DNT19FQ4RT6FJDCBSENJRCRPVK10IW8KKW1782101467",
        submitted_at: 1.minute.from_now,
        validated_at: 1.minute.from_now)

      get e_invoice_guest_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("wastays-e-invoice-SAH-300000001-DN.pdf")
    end
  end

  describe "GET /guest/bookings/:id" do
    before do
      booking.e_invoice_submissions.delete_all
    end

    it "shows e-invoice failure message when submission is rejected" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        status: "invalid",
        document_scenario: "guest_invoice",
        document_type: "01",
        error_details: { message: "Booking guest city must map to a valid Malaysia state code" })

      get guest_booking_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("E-Invoice submission failed")
      expect(response.body).to include("Booking guest city must map to a valid Malaysia state code")
    end
  end
end
