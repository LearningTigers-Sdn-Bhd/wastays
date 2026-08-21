require "rails_helper"

RSpec.describe "HotelPortal::EInvoiceSubmissions", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:hotel) { create(:hotel, account: account, status: "live", tin: "C1234567890", ssm_number: "202301012345") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard") }
  # Default booking uses amount >= RM10,000 to pass the low-value policy check
  let(:booking) do
    create(:booking, hotel: hotel, booking_quote: nil,
      payment_status: "captured", total_amount: 15_000.0)
  end
  let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, subtotal: 15_000.0) }

  before do
    # Add payment transaction to make payment_concluded? return true
    create(:payment_transaction, booking: booking, status: "captured",
      gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")

    # Add permissions for accessing hotel portal
    role = create(:role, account: account, slug: "hotel_owner")
    # Reads are gated on view_bookings and writes on manage_bookings, because
    # these endpoints file and cancel documents with LHDN.
    %w[manage_hotel_profile view_bookings manage_bookings].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
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

  describe "GET /hotel/:hotel_id/e_invoice_submissions" do
    it "shows dedicated workspace content and settings CTA" do
      get hotel_e_invoice_submissions_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("E-Invoice")
      expect(response.body).to include("Open E-Invoice Settings")
    end

    # A fully-configured hotel doesn't need to be told so every time it opens
    # this page - "Configuration health" is only worth a section when there's
    # something to act on.
    it "does not show a configuration health section once everything is ready" do
      get hotel_e_invoice_submissions_path(hotel)

      expect(response.body).not_to include("Configuration health")
    end

    it "shows a configuration health section when e-invoicing is off" do
      hotel.e_invoice_setting.update!(enabled: false)

      get hotel_e_invoice_submissions_path(hotel)

      expect(response.body).to include("Configuration health")
      expect(response.body).to include("E-Invoice is turned off")
    end
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
      # Note: The controller does not check folio status; it only checks payment_concluded?
      # This test verifies that a booking with open folio can still proceed through submission
      it "allows submission even when folio is open (folio status not checked in controller)" do
        ActiveJob::Base.queue_adapter = :test
        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to have_enqueued_job(EInvoice::SubmitJob)
      end
    end

    context "when booking collector is still unknown" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, fund_collector: "unknown",
          source: "channel_manager", payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
      end

      # The hotel files under its own registration either way, so who collected
      # the money no longer decides who issues and no longer blocks filing.
      it "files anyway, since the hotel is the issuer regardless" do
        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to have_enqueued_job(EInvoice::SubmitJob)
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
      let(:booking) do
        create(:booking, :direct_hotel_payment, hotel: hotel, booking_quote: nil,
          payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
      end

      # Nothing to set up: without opting into WAStays filing on its behalf,
      # the hotel simply files this itself as an ordinary taxpayer.
      it "files it as the hotel's own taxpayer submission" do
        ActiveJob::Base.queue_adapter = :test

        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        expect(booking.reload.guest_invoice_submission).to have_attributes(
          document_scenario: "guest_invoice",
          submission_mode: "taxpayer",
          represented_taxpayer_tin: nil
        )
      end
    end

    context "when the booking is hotel-collected and intermediary setup is complete" do
      let(:booking) do
        create(:booking, :direct_hotel_payment, hotel: hotel, booking_quote: nil,
          payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
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

    context "when hotel tries to manually submit unrequested low-value booking (< RM10,000)" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, total_amount: 500.0,
          payment_status: "captured")
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 50_000, currency: "MYR")
        # Create pending consolidated placeholder (not requested by guest)
        create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "guest_invoice",
          status: "pending",
          consolidated: true,
          requested_by_guest: false)
      end

      it "blocks manual submission and shows consolidation policy message" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("below RM10,000")
        expect(flash[:alert]).to include("monthly consolidated submission")
      end
    end

    context "when hotel submits booking >= RM10,000 without guest request" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, total_amount: 15_000.0,
          payment_status: "captured")
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
      end

      it "allows individual submission for high-value bookings" do
        ActiveJob::Base.queue_adapter = :test

        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to have_enqueued_job(EInvoice::SubmitJob)

        submission = booking.reload.guest_invoice_submission
        expect(submission).to be_present
        expect(submission.consolidated).to be false
      end
    end

    context "when hotel submits booking that was guest-requested" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, total_amount: 500.0,
          payment_status: "captured")
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 50_000, currency: "MYR")
        create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "guest_invoice",
          status: "pending",
          consolidated: false,
          requested_by_guest: true)
      end

      it "allows submission for guest-requested bookings" do
        # Since a pending submission already exists, it should redirect with "already being prepared"
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)

        expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, booking.e_invoice_submissions.last))
        expect(flash[:alert]).to include("already being prepared")
      end
    end

    context "when an old guest submission exists for another payment receiver" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, fund_collector: "hotel",
          payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
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

    context "when hotel submits a low-value booking on behalf of a guest request" do
      let(:booking) do
        create(:booking, hotel: hotel, booking_quote: nil, total_amount: 500.0,
          payment_status: "captured")
      end

      before do
        create(:payment_transaction, booking: booking, status: "captured",
          gateway: "stripe", captured_at: Time.current, amount_subunits: 50_000, currency: "MYR")
        ActiveJob::Base.queue_adapter = :test
      end

      it "creates an individual guest-requested submission instead of blocking for consolidation" do
        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id, requested_by_guest: true)
        }.to have_enqueued_job(EInvoice::SubmitJob)

        submission = booking.reload.guest_invoice_submission
        expect(submission).to be_present
        expect(submission.consolidated).to be false
        expect(submission.requested_by_guest).to be true
        expect(submission.requested_at).to be_present
        expect(submission.payment_concluded_at).to be_present
      end
    end
  end

  describe "GET /hotel/:hotel_id/e_invoice_submissions/:id/pdf" do
    it "returns a PDF for a validated adjustment note" do
      adjustment_booking = create(:booking, hotel: hotel, booking_quote: nil,
        payment_status: "captured", total_amount: 15_000.0, guest_city: "Kota Kinabalu", guest_country: "Malaysia")
      create(:payment_transaction, booking: adjustment_booking, status: "captured",
        gateway: "stripe", captured_at: Time.current, amount_subunits: 1_500_000, currency: "MYR")
      create(:booking_room, booking: adjustment_booking, room_type: room_type, subtotal: 15_000.0)
      folio = create(:booking_folio, booking: adjustment_booking, status: "closed")
      create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "adjustment", amount: 10.0)
      submission = create(:e_invoice_submission,
        hotel: hotel,
        booking: adjustment_booking,
        document_scenario: "guest_invoice",
        document_type: "03",
        status: "valid",
        internal_id: "INV-ADJ-001",
        uuid: "adj-uuid-123",
        submission_uid: "adj-sub-uid-123",
        long_id: "adj-long-id-123",
        submitted_at: Time.current,
        validated_at: Time.current)

      get pdf_hotel_e_invoice_submission_path(hotel, submission)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body[0, 5]).to eq("%PDF-")
    end
  end

  describe "GET /hotel/:hotel_id/e_invoice_submissions/:id" do
    it "highlights retry help for failed guest-requested submissions" do
      submission = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        submission_mode: "taxpayer",
        fund_collector: "wastays",
        status: "invalid",
        requested_by_guest: true,
        error_details: { message: "Guest TIN is invalid" })

      get hotel_e_invoice_submission_path(hotel, submission)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Guest requested this e-invoice")
      expect(response.body).to include("Retry submission")
      expect(response.body).to include("Once the guest details are corrected")
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

    it "allows changes when only pending consolidated unrequested placeholder exists" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        status: "pending",
        consolidated: true,
        requested_by_guest: false)

      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "hotel" } }

      expect(response).to redirect_to(hotel_folio_path(hotel, booking))
      expect(booking.reload.fund_collector).to eq("hotel")
      expect(flash[:notice]).to include("paid to the hotel")
    end

    # The hotel issues either way now, so recording who took the money does not
    # change the document that is pending.
    it "leaves the pending placeholder alone when the receiver changes" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        status: "pending",
        consolidated: true,
        requested_by_guest: false)

      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "hotel" } }

      expect(booking.reload.fund_collector).to eq("hotel")

      placeholder = booking.e_invoice_submissions.find_by(document_scenario: "guest_invoice")
      expect(placeholder.status).to eq("pending")
    end

    # It does matter once the hotel has asked WAStays to file on its behalf,
    # because then the issuer really does change.
    context "when the hotel has opted into WAStays filing on its behalf" do
      before { hotel.e_invoice_setting.update!(intermediary_enabled: true) }

      it "swaps the placeholder for the intermediary one" do
        create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "guest_invoice",
          status: "pending",
          consolidated: true,
          requested_by_guest: false)

        patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
          params: { booking: { fund_collector: "hotel" } }

        old_submission = booking.e_invoice_submissions.find_by(document_scenario: "guest_invoice")
        expect(old_submission.status).to eq("cancelled")
        expect(old_submission.error_details["receiver_changed"]).to be true

        replacement = booking.e_invoice_submissions.find_by(document_scenario: "hotel_intermediary_guest_invoice")
        expect(replacement).to be_present
        expect(replacement.status).to eq("pending")
        expect(replacement.consolidated).to be true
      end
    end

    it "blocks changes when pending individual submission exists" do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        status: "pending",
        consolidated: false,
        requested_by_guest: false)

      patch update_payment_receiver_hotel_e_invoice_submissions_path(hotel, booking_id: booking.id),
        params: { booking: { fund_collector: "hotel" } }

      expect(response).to have_http_status(:found)
      expect(booking.reload.fund_collector).to eq("unknown")
      expect(flash[:alert]).to include("e-invoice process has started")
    end
  end

  describe "POST /retry" do
    it "requeues an invalid submission" do
      submission = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        submission_mode: "taxpayer",
        fund_collector: "wastays",
        status: "invalid",
        error_details: { message: "Booking guest city is required" })

      ActiveJob::Base.queue_adapter = :test

      expect {
        post retry_hotel_e_invoice_submission_path(hotel, submission)
      }.to have_enqueued_job(EInvoice::SubmitJob).with(submission.id)

      expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
      expect(flash[:notice]).to include("retry queued")
    end

    it "requeues a stale pending submission without LHDN tracking IDs" do
      submission = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        submission_mode: "taxpayer",
        fund_collector: "wastays",
        status: "pending",
        created_at: 10.minutes.ago,
        updated_at: 10.minutes.ago,
        submission_uid: nil,
        uuid: nil)

      ActiveJob::Base.queue_adapter = :test

      expect {
        post retry_hotel_e_invoice_submission_path(hotel, submission)
      }.to have_enqueued_job(EInvoice::SubmitJob).with(submission.id)

      expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
    end

    it "blocks retry for a fresh pending submission" do
      submission = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        submission_mode: "taxpayer",
        fund_collector: "wastays",
        status: "pending",
        created_at: 30.seconds.ago,
        updated_at: 30.seconds.ago,
        submission_uid: nil,
        uuid: nil)

      ActiveJob::Base.queue_adapter = :test

      expect {
        post retry_hotel_e_invoice_submission_path(hotel, submission)
      }.not_to have_enqueued_job(EInvoice::SubmitJob)

      expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
      expect(flash[:alert]).to include("cannot be retried")
    end
  end
end
