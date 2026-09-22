require "rails_helper"

RSpec.describe "Public::Concierge::Stays features", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", total_amount: 500.0,
      currency: "MYR", guest_name: "Ahmad Zulkifli", guest_email: "ahmad@example.com")
  end
  let(:stay_access) { create(:concierge_stay_access, hotel: hotel, booking: booking) }
  let(:args) { [ hotel.unique_id, hotel.public_id, stay_access.stay_access_id ] }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    create(:refund_policy, refund_percentage: 80, min_days_before_checkin: 3)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "1201")
    post concierge_stay_verification_path(*args), params: { confirmation_token: booking.confirmation_token }
  end

  describe "the stay page" do
    it "shows the stay facts and the actions" do
      get concierge_stay_path(*args)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ahmad")
      expect(response.body).to include("1201")
      expect(response.body).to include(booking.confirmation_token.upcase)
      expect(response.body).to include("Housekeeping")
      expect(response.body).to include("Check Out")
      expect(response.body).to include("Booking receipt")
    end

    it "hides the invoice while the guest is in house" do
      get concierge_stay_path(*args)

      expect(response.body).not_to include("documents/invoice")
    end

    it "offers the invoice after check-out" do
      booking.status_transition_event = "check_out"
      booking.update!(status: "completed", checked_out_at: 1.day.ago)

      get concierge_stay_path(*args)

      expect(response.body).to include("documents/invoice")
    end
  end

  describe "documents" do
    it "sends the receipt PDF" do
      get concierge_stay_document_path(*args, :receipt)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "sends an unavailable document back to the stay page" do
      get concierge_stay_document_path(*args, :invoice)

      expect(response).to redirect_to(concierge_stay_path(*args))
      expect(flash[:alert]).to include("No finalized guest invoice")
    end

    it "does not route a document kind it does not know" do
      get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/stay/#{stay_access.stay_access_id}/documents/passport"

      expect(response.body).not_to include("Content-Disposition")
    end

    it "demands a stay session" do
      other = create(:booking, hotel: hotel, status: "checked_in")
      other_access = create(:concierge_stay_access, hotel: hotel, booking: other)

      get concierge_stay_document_path(hotel.unique_id, hotel.public_id, other_access.stay_access_id, :receipt)

      expect(response.body).to include("Booking confirmation code")
    end
  end

  describe "guest requests" do
    it "shows the housekeeping form" do
      get concierge_new_stay_request_path(*args, kind: "housekeeping")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ask for housekeeping")
    end

    it "falls back to housekeeping for a kind it does not know" do
      get concierge_new_stay_request_path(*args, kind: "massage")

      expect(response.body).to include("Ask for housekeeping")
    end

    it "creates a housekeeping request" do
      expect {
        post concierge_stay_requests_path(*args), params: { kind: "housekeeping", details: "Two more towels." }
      }.to change { booking.housekeeping_requests.count }.by(1)

      expect(response).to redirect_to(concierge_stay_path(*args))
    end

    it "shows the error for blank details" do
      post concierge_stay_requests_path(*args), params: { kind: "housekeeping", details: "" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Details cannot be blank")
    end
  end

  describe "check-out requests" do
    it "creates the request" do
      expect {
        post concierge_stay_check_outs_path(*args), params: { guest_notes: "Leaving at 9." }
      }.to change { booking.check_out_requests.count }.by(1)

      expect(response).to redirect_to(concierge_stay_path(*args))
    end

    it "refuses a second open request" do
      post concierge_stay_check_outs_path(*args)
      post concierge_stay_check_outs_path(*args)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already pending")
    end
  end

  describe "refund requests" do
    it "shows the form with the amount the guest paid" do
      get concierge_stay_refund_path(*args)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How much are you asking for?")
      expect(response.body).to include("500.00")
    end

    it "creates a pending request and leaves the booking status alone" do
      post concierge_stay_refunds_path(*args), params: {
        refund_request: {
          refund_amount: "120.50", reason: "Charged twice for the minibar.",
          bank_name: "Maybank", account_holder_name: "Ahmad Zulkifli",
          account_number: "1234567890", account_type: "savings"
        }
      }

      expect(response).to redirect_to(concierge_stay_path(*args))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.refund_request.refund_amount).to eq(120.50)
      expect(booking.refund_request.status).to eq("pending")
    end

    it "refuses more than the guest paid" do
      post concierge_stay_refunds_path(*args), params: {
        refund_request: {
          refund_amount: "900", reason: "Everything",
          bank_name: "Maybank", account_holder_name: "Ahmad Zulkifli",
          account_number: "1234567890", account_type: "savings"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("MYR 500.00")
      expect(booking.reload.refund_request).to be_nil
    end

    it "shows the status once a request is open" do
      create(:refund_request, booking: booking, status: "pending", refund_amount: 100.0)

      get concierge_stay_refund_path(*args)

      expect(response.body).to include("Pending")
      expect(response.body).not_to include("How much are you asking for?")
    end
  end

  describe "the e-invoice" do
    it "reports idle when nothing was requested" do
      get concierge_stay_e_invoice_path(*args)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Idle")
    end

    it "offers the download when one is ready" do
      create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "01")

      get concierge_stay_e_invoice_path(*args)

      expect(response.body).to include("Download the e-invoice")
    end

    it "answers the status as JSON" do
      get concierge_stay_e_invoice_status_path(*args)

      expect(response.parsed_body["status"]).to eq("idle")
    end

    it "shows the reason a request is refused" do
      post concierge_stay_e_invoice_request_path(*args)

      expect(response).to redirect_to(concierge_stay_e_invoice_path(*args))
      expect(flash[:alert]).to be_present
    end
  end

  describe "do not disturb" do
    it "switches the room flag" do
      patch concierge_stay_do_not_disturb_path(*args)

      expect(response).to redirect_to(concierge_stay_path(*args))
      expect(flash[:alert]).to be_nil
    end
  end
end
