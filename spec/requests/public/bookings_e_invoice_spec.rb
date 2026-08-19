require "rails_helper"

RSpec.describe "Public::Bookings e-invoice", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard Room") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      confirmation_token: "WS-EINVTEST1",
      guest_name: "John Doe",
      guest_email: "john@example.com",
      guest_phone: "+60111234567",
      guest_document_type: "ic",
      guest_government_id: "820916125537",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_country: "Malaysia",
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
      subtotal: 200.0,
      room_type_snapshot: { "name" => "Standard Room" }
    )
  end

  describe "GET /bookings/:id/e_invoice" do
    before do
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
    end

    it "returns a PDF for a valid confirmation token with ready e-invoice" do
      get e_invoice_booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline")
      expect(response.headers["Content-Disposition"]).to include("wastays-e-invoice-SAH-300000001.pdf")
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

      get e_invoice_booking_path(booking.confirmation_token, submission_id: original.id)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("wastays-e-invoice-SAH-300000001.pdf")
    end

    it "returns 404 when booking has no ready e-invoice" do
      booking.e_invoice_submissions.delete_all

      get e_invoice_booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:not_found)
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
        validated_at: 1.minute.from_now
      )

      get e_invoice_booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("wastays-e-invoice-SAH-300000001-DN.pdf")
    end
  end

  describe "POST /bookings/:id/request_e_invoice" do
    before do
      create(:payment_transaction, booking: booking, status: "captured",
        gateway: "stripe", captured_at: Time.current, amount_subunits: 20_000, currency: "MYR")
      ActiveJob::Base.queue_adapter = :test
    end

    it "enqueues a guest-requested e-invoice from the public booking page" do
      expect {
        post request_e_invoice_booking_path(booking.confirmation_token)
      }.to have_enqueued_job(EInvoice::AutoIssueJob).with(booking.id, requested_by_guest: true)

      expect(response).to redirect_to(booking_path(booking.confirmation_token))
    end

    it "blocks duplicate pending individual requests" do
      create(:e_invoice_submission,
        hotel: hotel, booking: booking,
        document_scenario: "guest_invoice",
        status: "pending", consolidated: false, requested_by_guest: true)

      expect {
        post request_e_invoice_booking_path(booking.confirmation_token)
      }.not_to have_enqueued_job(EInvoice::AutoIssueJob)

      expect(response).to redirect_to(booking_path(booking.confirmation_token))
      follow_redirect!
      expect(response.body).to include("already being prepared")
    end
  end
end
