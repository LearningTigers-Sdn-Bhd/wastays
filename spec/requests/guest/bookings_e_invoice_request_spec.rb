require "rails_helper"

RSpec.describe "Guest::Bookings#request_e_invoice", type: :request do
  let(:guest) do
    create(:guest, name: "Invoice Guest", email: "inv@example.com",
      phone: "+60123456789", country: "Malaysia",
      document_type: "ic", government_id: "820916125537")
  end
  let(:hotel) { create(:hotel, status: "approved") }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard") }

  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Invoice Guest",
      guest_email: "inv@example.com",
      guest_phone: "+60123456789",
      guest_document_type: "ic",
      guest_government_id: "820916125537",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_country: "Malaysia",
      total_amount: 300.0, currency: "MYR",
      payment_status: "captured",
      check_in: Date.current, check_out: Date.current + 2.days)
  end

  before do
    create(:booking_room, booking: booking, room_type: room_type, quantity: 1, subtotal: 300.0)
    create(:payment_transaction, booking: booking, status: "captured",
      gateway: "stripe", captured_at: Time.current, amount_subunits: 30_000, currency: "MYR")
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
    follow_redirect!
  end

  describe "POST /guest/bookings/:id/request_e_invoice" do
    context "when all conditions are met" do
      it "redirects with notice and enqueues the job" do
        expect {
          post request_e_invoice_guest_booking_path(booking)
        }.to have_enqueued_job(EInvoice::AutoIssueJob).with(booking.id, requested_by_guest: true)

        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("e-invoice request has been submitted")
      end
    end

    context "when payment has not concluded" do
      before do
        booking.payment_transactions.destroy_all
        booking.update!(payment_status: "pending")
      end

      it "redirects back with alert" do
        post request_e_invoice_guest_booking_path(booking)
        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("payment has not concluded")
      end
    end

    context "when outside the same payment month" do
      before do
        booking.payment_transactions.update_all(captured_at: 2.months.ago)
      end

      it "redirects back with alert" do
        post request_e_invoice_guest_booking_path(booking)
        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("same calendar month")
      end
    end

    context "when an e-invoice has already been issued" do
      before do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "submitted", requested_by_guest: true)
      end

      it "redirects back with alert" do
        post request_e_invoice_guest_booking_path(booking)
        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("already been issued")
      end
    end

    context "when a pending consolidated placeholder exists but guest requests" do
      before do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: true, requested_by_guest: false)
      end

      it "allows guest request even with pending consolidated placeholder" do
        expect {
          post request_e_invoice_guest_booking_path(booking)
        }.to have_enqueued_job(EInvoice::AutoIssueJob).with(booking.id, requested_by_guest: true)

        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("e-invoice request has been submitted")
      end
    end

    context "when a pending individual submission already exists from earlier request" do
      before do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: false, requested_by_guest: true)
      end

      it "returns already-being-prepared message without enqueueing duplicate" do
        expect {
          post request_e_invoice_guest_booking_path(booking)
        }.not_to have_enqueued_job(EInvoice::AutoIssueJob)

        expect(response).to redirect_to(guest_booking_path(booking))
        follow_redirect!
        expect(response.body).to include("already being prepared")
      end
    end

    context "when not logged in" do
      before { delete guest_logout_path }

      it "redirects to login" do
        post request_e_invoice_guest_booking_path(booking)
        expect(response).to redirect_to(guest_login_path)
      end
    end
  end
end
