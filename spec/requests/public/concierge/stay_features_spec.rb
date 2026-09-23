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
      expect(response.body).to include("Booking reference number", booking.formatted_reservation_number)
      expect(response.body).to include("Booking confirmation code")
      expect(response.body).to include(booking.confirmation_token.upcase)
      expect(response.body).to include("Housekeeping")
      expect(response.body).to include("Cleaning or supplies")
      expect(response.body).to include("Check Out")
      expect(response.body).to include("Tell the front desk")
      expect(response.body).to include("Booking receipt")
    end

    it "puts the stay summary before the stay actions and the hotel services" do
      get concierge_stay_path(*args)

      page = Nokogiri::HTML(response.body)
      lines = {
        summary: ".guest-stay-summary",
        actions: ".guest-stay-overview__actions",
        services: ".guest-stay-overview__services",
        more: "details.guest-more-actions"
      }.transform_values { |selector| page.at_css(selector).line }

      expect(lines.sort_by(&:last).map(&:first)).to eq(%i[summary actions services more])
    end

    it "shows hotel services as separate cards and booking actions in a closed disclosure" do
      get concierge_stay_path(*args)

      page = Nokogiri::HTML(response.body)
      services = page.at_css(".guest-stay-overview__services")
      more_actions = page.at_css("details.guest-more-actions")

      expect(services.css("a.guest-action-card").map { |card| card.text.strip }).to include(
        "Report a problem Tell us what is wrong",
        "Recommendations Places and guest offers",
        "Property Contacts Phone, WhatsApp, email and map"
      )
      expect(more_actions.at_css("summary").text).to include("More Actions")
      expect(more_actions.at_css("summary .guest-more-actions__icon[aria-hidden='true']")).to be_present
      expect(more_actions["open"]).to be_nil
      expect(more_actions.css("a.guest-card__row").map(&:text).join).to include("Booking receipt", "E-invoice")
      expect(page.css("[role='switch']")).to be_empty
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
      expect(response.headers["Content-Disposition"]).to include("inline")
    end

    it "opens the receipt and the e-invoice in a new tab, and says so" do
      get concierge_stay_path(*args)

      page = Nokogiri::HTML(response.body)

      [ concierge_stay_document_path(*args, :receipt), concierge_stay_e_invoice_path(*args) ].each do |href|
        row = page.at_css("a.guest-card__row[href='#{href}']")

        expect(row["target"]).to eq("_blank")
        expect(row["rel"]).to eq("noopener")
        expect(row.at_css(".sr-only").text).to include("opens in a new tab")
      end
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

    it "draws the request form on the page, not in a card, with a labelled required field" do
      get concierge_new_stay_request_path(*args, kind: "housekeeping")

      page = Nokogiri::HTML(response.body)
      field = page.at_css(".guest-stay-form__body textarea#details")
      button = page.at_css(".guest-stay-form__body button[type='submit']")

      expect(page.at_css(".guest-stay-form__body .guest-card")).to be_nil
      expect(page.at_css("label[for='details']").text).to include("What do you need?", "(required)")
      expect(field["required"]).to be_present
      expect(field["autofocus"]).to be_nil
      expect(field["placeholder"]).to start_with("For example:")
      expect(button["data-turbo-submits-with"]).to eq("Sending…")
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
      expect(response.body).to include("Refund amount (MYR)")
      expect(response.body).to include("500.00")
      expect(Nokogiri::HTML(response.body).at_css(".guest-select select#refund_request_bank_name option[value='Maybank']")).to be_present
    end

    it "hides the other bank field until the guest picks Other bank" do
      get concierge_stay_refund_path(*args)

      page = Nokogiri::HTML(response.body)
      field = page.at_css("[data-other-choice-target='field']")

      expect(page.at_css("select#refund_request_bank_name option[value='#{BankCatalog::OTHER}']").text).to eq("Other bank")
      expect(field["hidden"]).to be_present
      expect(field.at_css("input#refund_request_other_bank_name")["disabled"]).to be_present
    end

    it "stores the typed name for a bank that is not listed" do
      post concierge_stay_refunds_path(*args), params: {
        refund_request: {
          refund_amount: "100", bank_name: BankCatalog::OTHER, other_bank_name: " DBS Bank ",
          account_holder_name: "Ahmad Zulkifli", account_number: "123456789", account_type: "savings"
        }
      }

      expect(booking.reload.refund_request.bank_name).to eq("DBS Bank")
    end

    it "brings the typed bank name back under Other bank when the form fails" do
      post concierge_stay_refunds_path(*args), params: {
        refund_request: { refund_amount: "", bank_name: BankCatalog::OTHER, other_bank_name: "DBS Bank" }
      }

      page = Nokogiri::HTML(response.body)

      expect(page.at_css("select#refund_request_bank_name option[selected]")["value"]).to eq(BankCatalog::OTHER)
      expect(page.at_css("[data-other-choice-target='field']")["hidden"]).to be_nil
      expect(page.at_css("input#refund_request_other_bank_name")["value"]).to eq("DBS Bank")
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
      expect(response.body).not_to include("Refund amount (MYR)")
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

      expect(response.body).to include("Open the e-invoice")
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

  # The stay page has no phone-only twin, so what a guest is offered cannot
  # depend on how their user agent string is read.
  describe "one page for every device" do
    it "serves the same stay page to phones and desktops" do
      bodies = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].map do |user_agent|
        get concierge_stay_path(*args), headers: { "HTTP_USER_AGENT" => user_agent }
        response.body
      end

      expect(bodies.first).to eq(bodies.last)
    end

    it "puts the four blocks in mobile reading order" do
      get concierge_stay_path(*args)

      page = Nokogiri::HTML(response.body)
      blocks = page.css(".guest-stay-overview > *").map { |block| block["class"] }

      expect(blocks).to match([
        include("guest-stay-overview__greeting"),
        include("guest-stay-overview__stay"),
        include("guest-stay-overview__main"),
        include("guest-stay-overview__more")
      ])
    end

    it "leads a form page with the compact stay card as the way back" do
      get concierge_new_stay_request_path(*args, kind: "housekeeping")

      page = Nokogiri::HTML(response.body)
      blocks = page.css(".guest-stay-form > *").map { |block| block["class"] }
      compact = page.at_css(".guest-stay-form__compact a.guest-stay-compact")

      expect(blocks).to match([
        include("guest-stay-form__compact"),
        include("guest-stay-form__header"),
        include("guest-stay-form__summary"),
        include("guest-stay-form__body")
      ])
      expect(compact["href"]).to eq(concierge_stay_path(*args))
      expect(compact.text.squish).to include("Back to my stay.", "Room 1201")
      expect(page.at_css(".guest-stay-form__summary .guest-stay-summary")).to be_present
    end
  end

  describe "the states a stay passes through" do
    it "still offers the services while the guest is due out" do
      booking.status_transition_event = "detect_due_out"
      booking.update!(status: "due_out_detected")

      get concierge_stay_path(*args)

      expect(response.body).to include("Housekeeping")
      expect(response.body).to include("Check Out")
    end

    it "drops the in-house actions once the guest has checked out" do
      booking.status_transition_event = "check_out"
      booking.update!(status: "completed", checked_out_at: 1.hour.ago)

      get concierge_stay_path(*args)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Ask for housekeeping")
      expect(response.body).to include("Booking receipt")
    end
  end

  # The stay actions redirect with a notice or an alert, and nothing on the
  # page drew either. A guest sent a request to the hotel and landed back on a
  # page that looked exactly as it had a moment before.
  describe "what the page says after an action" do
    it "shows the notice after a housekeeping request" do
      post concierge_stay_requests_path(*args), params: { kind: "housekeeping", details: "Two more towels." }
      follow_redirect!

      expect(response.body).to include("We have your request. The hotel team is on it.")
      expect(response.body).to include(%(data-variant="success"))
    end

    it "shows the notice after a check-out request" do
      post concierge_stay_check_outs_path(*args), params: { guest_notes: "" }
      follow_redirect!

      expect(response.body).to include("The front desk has your check-out request.")
    end

    it "shows the alert when an e-invoice request is refused" do
      post concierge_stay_e_invoice_request_path(*args)
      follow_redirect!

      expect(response.body).to include(%(data-variant="danger"))
      expect(response.body).to include(%(role="alert"))
    end
  end

  # The hero is a sticky bar, not a link. It sits where a thumb rests while
  # scrolling, so a link there invites an accidental tap.
  describe "the hero" do
    def hero
      response.body[%r{<div class="guest-hero".*?</h1>}m]
    end

    it "sticks without a link on a stay page" do
      get concierge_stay_path(*args)

      expect(hero).to include('data-controller="concierge-hero"')
      expect(hero).to include('data-concierge-hero-target="sentinel"')
      expect(hero).to include(hotel.name)
      expect(hero).not_to include("<a ")
    end

    it "sticks without a link on a form page" do
      get concierge_stay_check_out_path(*args)

      expect(hero).to include('data-controller="concierge-hero"')
      expect(hero).not_to include("<a ")
    end

    it "sticks without a link on the concierge home" do
      get concierge_home_path(hotel.unique_id, hotel.public_id)

      expect(hero).to include('data-controller="concierge-hero"')
      expect(hero).not_to include("<a ")
    end
  end
end
