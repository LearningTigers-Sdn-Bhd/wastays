require "rails_helper"

RSpec.describe "HotelPortal::EInvoiceSubmissions", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:booking) { create(:booking, hotel: hotel, booking_quote: nil) }
  let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
  let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 200.0, quantity: 1) }

  before do
    # Add permissions for accessing hotel portal
    role = create(:role, account: account, slug: "hotel_owner")
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |p| p.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Enable e-invoice
    create(:e_invoice_setting, hotel: hotel, enabled: true)

    allow(Rails.application.credentials).to receive(:myinvois).and_return(
      double(
        to_h: {
          tin: "C1234567890",
          brn: "202301012345",
          name: "Jesselton Pixel Sdn Bhd",
          phone: "+60111234567",
          email: "finance@wastays.com",
          city: "Kota Kinabalu",
          postal_code: "88000",
          state_code: "12",
          address: "123 Street"
        }
      )
    )

    # Sign in
    sign_in_as(user)
  end

  describe "POST /create" do
    context "when e-invoice setting is disabled" do
      before do
        hotel.e_invoice_setting.update!(enabled: false)
      end

      it "redirects back with alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("E-invoice is turned off")
      end
    end

    context "when booking folio is not closed" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "open") }

      it "redirects back with alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("must have a closed folio")
      end
    end

    context "when booking collector is still unknown" do
      let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, fund_collector: "unknown", source: "channel_manager") }

      it "blocks submission with actionable alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("Please confirm whether the guest paid WAStays or paid the hotel directly")
      end
    end

    context "when validation passes" do
      it "enqueues SubmitJob and redirects to submission page" do
        ActiveJob::Base.queue_adapter = :test
        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to have_enqueued_job(EInvoice::SubmitJob)

        submission = booking.reload.guest_invoice_submission
        expect(submission).to be_present
        expect(submission.status).to eq("pending")
        expect(submission.document_scenario).to eq("guest_invoice")
        expect(enqueued_jobs.last[:args]).to eq([ submission.id ])
        expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
        expect(flash[:notice]).to include("being prepared")
      end

      it "reuses existing pending submission instead of creating duplicate" do
        submission = create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01",
          submission_mode: "taxpayer",
          fund_collector: "wastays",
          status: "pending")

        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.not_to change(EInvoiceSubmission, :count)

        expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
        expect(flash[:alert]).to include("already being prepared")
      end
    end

    context "when the booking is hotel-collected but intermediary setup is incomplete" do
      let(:booking) { create(:booking, :direct_hotel_payment, hotel: hotel, booking_quote: nil) }

      it "redirects back with an actionable alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("Hotel-issued e-invoices are not ready yet")
      end
    end

    context "when the booking is hotel-collected and intermediary setup is complete" do
      let(:booking) { create(:booking, :direct_hotel_payment, hotel: hotel, booking_quote: nil) }

      before do
        hotel.e_invoice_setting.update!(
          intermediary_enabled: true,
          supplier_msic_code: "55101",
          supplier_business_description: "Hotel accommodation services",
          supplier_address_line1: "1 Jalan Hotel",
          supplier_city: "Kota Kinabalu",
          supplier_postal_code: "88000",
          supplier_state_code: "12",
          supplier_contact_phone: "+6088123456",
          supplier_contact_email: "finance@hotel.test"
        )
      end

      it "queues the submission and snapshots intermediary mode" do
        ActiveJob::Base.queue_adapter = :test

        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        submission = booking.reload.guest_invoice_submission
        expect(submission).to have_attributes(
          document_scenario: "hotel_intermediary_guest_invoice",
          submission_mode: "intermediary",
          fund_collector: "hotel",
          represented_taxpayer_tin: hotel.e_invoice_setting.hotel_tin
        )
      end
    end

    context "when an old guest submission exists for another payment receiver" do
      let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, fund_collector: "hotel") }

      before do
        hotel.e_invoice_setting.update!(
          intermediary_enabled: true,
          supplier_msic_code: "55101",
          supplier_business_description: "Hotel accommodation services",
          supplier_address_line1: "1 Jalan Hotel",
          supplier_city: "Kota Kinabalu",
          supplier_postal_code: "88000",
          supplier_state_code: "12",
          supplier_contact_phone: "+6088123456",
          supplier_contact_email: "finance@hotel.test"
        )

        create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01",
          submission_mode: "taxpayer",
          fund_collector: "wastays",
          status: "invalid")
      end

      it "creates a new submission for the current scenario instead of reusing the old one" do
        ActiveJob::Base.queue_adapter = :test

        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to change { booking.reload.e_invoice_submissions.count }.by(1)

        expect(booking.reload.e_invoice_submissions.for_scenario("hotel_intermediary_guest_invoice").count).to eq(1)
      end
    end
  end

  describe "PATCH /update_payment_receiver" do
    let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, fund_collector: "unknown", source: "channel_manager") }

    it "saves who received the payment" do
      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "hotel" } }

      expect(response).to redirect_to(hotel_folio_path(hotel, booking))
      expect(booking.reload.fund_collector).to eq("hotel")
      expect(flash[:notice]).to include("paid to the hotel")
    end

    it "rejects invalid values" do
      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "unknown" } }

      expect(response).to redirect_to(hotel_folio_path(hotel, booking))
      expect(flash[:alert]).to include("Please choose whether WAStays or the hotel received the guest payment")
    end

    it "blocks changes after a guest e-invoice is already being processed" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        submission_mode: "taxpayer",
        fund_collector: "wastays",
        status: "submitted")

      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "hotel" } }

      expect(response).to have_http_status(:found)
      expect(booking.reload.fund_collector).to eq("unknown")
      expect(flash[:alert]).to include("cannot change who received the payment")
    end
  end
end
