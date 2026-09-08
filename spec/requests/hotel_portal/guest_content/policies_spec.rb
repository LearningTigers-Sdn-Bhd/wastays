# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::Policies", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:sheet_headers) { { "Turbo-Frame" => "settings_action_sheet" } }
  let(:sheet_submit_headers) { sheet_headers.merge("Accept" => Mime[:turbo_stream].to_s) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end

    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def headings(response)
    response.parsed_body.css("h2").map { |heading| heading.text.squish }
  end

  describe "the sub-tabs" do
    it "offers all five sections on every policy page" do
      get hotel_policy_reservations_path(hotel)

      labels = response.parsed_body.css("[data-testid='guest-content-subtabs'] a").map { |link| link.text.squish }
      expect(labels).to eq([ "Reservation", "Room", "Payment & Deposits", "House Rules", "Other Policies" ])
    end
  end

  describe "Reservation" do
    it "reads the policies Room Revenue owns, and links back to them" do
      create(:hotel_reservation_policy, :no_show, hotel: hotel)

      get hotel_policy_reservations_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(headings(response)).to include("Reservation Policies")
      expect(response.body).to include("1 night at room rate")
      expect(response.body).to include(hotel_room_revenue_path(hotel))
    end

    it "says how many policies the hotel has still to set" do
      get hotel_policy_reservations_path(hotel)

      expect(response.body).to include("4 policies not set yet")
    end

    it "shows the guest note beside the charge it explains" do
      create(:hotel_reservation_policy, hotel: hotel, description: "Waived for a delayed flight.")

      get hotel_policy_reservations_path(hotel)

      expect(response.body).to include("Waived for a delayed flight.")
      expect(response.body).to include("Edit note")
    end
  end

  describe "the guest note sheet" do
    let(:policy) { create(:hotel_reservation_policy, hotel: hotel) }

    it "opens on an active policy and shows the charge it explains" do
      get edit_hotel_policy_reservation_note_path(hotel, policy)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Late checkout note")
      expect(response.body).to include("Staff enters amount")
    end

    it "saves the note" do
      patch hotel_policy_reservation_note_path(hotel, policy), params: {
        hotel_reservation_policy: { description: "Waived for a delayed flight." }
      }

      expect(response).to redirect_to(hotel_policy_reservations_path(hotel))
      expect(policy.reload.description).to eq("Waived for a delayed flight.")
    end

    # Room Revenue owns the charge. A note save must not touch it, or the two
    # pages stop meaning different things.
    it "leaves the charge alone" do
      policy.update!(pricing_type: "fixed", rate_value: 50, active: true)

      patch hotel_policy_reservation_note_path(hotel, policy), params: {
        hotel_reservation_policy: { description: "Ask the front desk.", pricing_type: "manual", rate_value: "999", active: "0" }
      }

      policy.reload
      expect(policy.pricing_type).to eq("fixed")
      expect(policy.rate_value).to eq(50)
      expect(policy).to be_active
    end

    # An off policy posts nothing, so a note on it would explain a charge that
    # never happens.
    it "refuses a policy the hotel switched off" do
      policy.update!(active: false)

      get edit_hotel_policy_reservation_note_path(hotel, policy)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Room" do
    it "reads occupancy, smoking, and pets from the room type" do
      create(:room_type, hotel: hotel, name: "Family Suite", max_adults: 4, max_children: 2, pets_allowed: true)

      get hotel_policy_rooms_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Family Suite")
      expect(response.body).to include(hotel_room_types_path(hotel))
      expect(headings(response)).to include("Room Limits", "Room Terms")
    end

    it "saves the extra room terms a column cannot hold" do
      patch hotel_policy_rooms_path(hotel), params: {
        hotel_knowledge_document: { content: "A child is a guest under 12 years old." }
      }

      expect(response).to redirect_to(hotel_policy_rooms_path(hotel))
      document = hotel.knowledge_documents.where(category: "policy").with_policy_key("room_terms").sole
      expect(document.content).to eq("A child is a guest under 12 years old.")
    end
  end

  describe "Payment and Deposits" do
    it "saves the card, then shows it back" do
      patch hotel_policy_payments_path(hotel), params: {
        hotel_knowledge_document: { content: "Payment is due in full at check-in." }
      }
      follow_redirect!

      expect(response.body).to include("Payment is due in full at check-in.")
      expect(hotel.knowledge_documents.with_policy_key("payment_and_deposits").count).to eq(1)
    end
  end

  describe "House Rules" do
    it "saves the card and points staff at Contact and Escalation for numbers" do
      patch hotel_policy_house_rules_path(hotel), params: {
        hotel_knowledge_document: { content: "Quiet hours run from 10 PM." }
      }
      follow_redirect!

      expect(response.body).to include("Quiet hours run from 10 PM.")
      expect(response.body).to include(hotel_guest_contact_path(hotel))
    end

    # The rules and the numbers a guest calls sit side by side, so a hotel
    # writing the rules can see what it must not repeat.
    it "shows the emergency contacts beside the rules, read-only" do
      hotel.create_guest_contact!(emergency_phone: "+60 3 1234 5600", emergency_services_number: "999")

      get hotel_policy_house_rules_path(hotel)

      body = response.parsed_body
      expect(body.at_css("[data-testid='house-rules-layout']")["class"]).to include("lg:grid-cols-2")
      expect(body.css("[data-testid='house-rules-layout'] > *").size).to eq(2)

      phone = body.at_css("input[name='hotel_guest_contact[emergency_phone]']")
      expect(phone[:value]).to eq("+60 3 1234 5600")
      expect(phone[:readonly]).to be_present
      expect(body.at_css("textarea[name='hotel_guest_contact[emergency_instructions]']")[:readonly]).to be_present
    end

    it "renders without a contact record on file" do
      get hotel_policy_house_rules_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Not on file")
    end
  end

  describe "Other Policies" do
    it "lists the policies a hotel named itself" do
      create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

      get hotel_knowledge_policies_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Parking")
    end

    # The row carries one trigger, not a row of buttons. The assertion names the
    # menu items because a dropdown that opens on nothing is the failure to catch.
    it "puts the row actions in a dropdown menu" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

      get hotel_knowledge_policies_path(hotel)

      expect(response.body).to include("guest-content-documents-table")
      expect(response.body).to include("Actions for Parking")
      expect(response.body).to include(edit_hotel_knowledge_policy_path(hotel, document))
      expect(response.body).to include("Remove")
    end

    # The columns say what the page will hold. Hiding them until the first save
    # makes the page change shape under the operator.
    it "keeps the table columns when there is nothing in the list yet" do
      get hotel_knowledge_policies_path(hotel)

      body = Nokogiri::HTML(response.body)
      table = body.at_css("[data-testid='guest-content-documents-table']")
      expect(table).to be_present
      expect(table.css("thead th").map { |cell| cell.text.squish }).to eq([ "Policy", "Status", "Source", "Effective date", "Action" ])
      expect(table.at_css("tbody .panel-empty-state")).to be_present
      expect(body.text).to include("No other policies yet")
    end

    it "opens the add form in the settings sheet" do
      get new_hotel_knowledge_policy_path(hotel), headers: sheet_headers

      body = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.at_css("turbo-frame#settings_action_sheet dialog#new-guest-content-document-sheet")).to be_present
      # The sheet footer submits the form by id, so the form must carry that id.
      expect(body.at_css("form#new-guest-content-document-form")).to be_present
    end

    it "opens the edit form in the settings sheet" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

      get edit_hotel_knowledge_policy_path(hotel, document), headers: sheet_headers

      body = Nokogiri::HTML(response.body)
      expect(body.at_css("turbo-frame#settings_action_sheet dialog#edit-guest-content-document-sheet")).to be_present
      expect(body.at_css("form#edit-guest-content-document-#{document.id}-form")).to be_present
    end

    it "closes the sheet and returns to the list after a save" do
      post hotel_knowledge_policies_path(hotel), params: {
        hotel_knowledge_document: { title: "Parking", content: "Valet parking is free." }
      }, headers: sheet_submit_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("complete_sheet")
      expect(response.body).to include(hotel_knowledge_policies_path(hotel))
      expect(hotel.knowledge_documents.where(category: "policy").sole.title).to eq("Parking")
    end

    it "keeps a validation error inside the sheet" do
      post hotel_knowledge_policies_path(hotel), params: {
        hotel_knowledge_document: { title: "", content: "" }
      }, headers: sheet_submit_headers

      body = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body.at_css("turbo-frame#settings_action_sheet dialog#new-guest-content-document-sheet")).to be_present
      expect(body.at_css("[role='alert']").text.squish).to include("could not be saved")
    end

    it "shows one policy in the detail sheet" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy",
        title: "Parking", content: "Valet runs 07:00 to 23:00.", embedding_status: "indexed")
      create(:hotel_knowledge_chunk, document: document, content: "Valet runs 07:00 to 23:00.")

      get hotel_knowledge_policy_path(hotel, document), headers: sheet_headers

      body = Nokogiri::HTML(response.body)
      sheet = body.at_css("turbo-frame#settings_action_sheet dialog#guest-content-document-sheet")
      expect(sheet).to be_present
      # The header is chrome and never names the record. The body does.
      expect(sheet.at_css("#guest-content-document-sheet-title").text.squish).to eq("Policy details")
      expect(sheet.at_css("h3").text.squish).to eq("Parking")
      expect(sheet.text).to include("Valet runs 07:00 to 23:00.")
      expect(sheet.text).to include("Prepared sections (1)")
    end

    it "offers the file instead of the text when a PDF is attached" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy",
        title: "Group terms", source_type: "pdf")
      document.file.attach(io: StringIO.new("%PDF-1.4"), filename: "group-terms.pdf", content_type: "application/pdf")

      get hotel_knowledge_policy_path(hotel, document), headers: sheet_headers

      sheet = Nokogiri::HTML(response.body).at_css("dialog#guest-content-document-sheet")
      expect(sheet.text).to include("group-terms.pdf")
      expect(sheet.css("a.panel-button").map { |link| link.text.squish }).to include("Open", "Download")
      # Nothing has been chunked yet, so the section says so rather than sitting empty.
      expect(sheet.text).to include("Still reading the file.")
    end

    it "puts the recovery action in the sheet when preparation failed" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "sk-test")
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy",
        title: "Parking", content: "Valet.")
      # A content change resets the status, so the failure is written after the save.
      document.update_columns(embedding_status: "failed", metadata: { "last_error" => "Timed out after 30s." })

      get hotel_knowledge_policy_path(hotel, document), headers: sheet_headers

      sheet = Nokogiri::HTML(response.body).at_css("dialog#guest-content-document-sheet")
      alert = sheet.at_css("[role='alert']")
      expect(alert.text.squish).to include("This policy is not ready")
      expect(alert.text.squish).to include("Timed out after 30s.")
      expect(alert.css(".panel-button").map { |button| button.text.squish }).to eq([ "Try again" ])
    end

    # An FAQ saved from indexed form fields stores its pairs as a Hash keyed by
    # position. The repeater used to walk that Hash and raise on the first pair.
    it "opens the FAQ edit sheet when the pairs are stored keyed by position" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "Check-in")
      document.update_columns(metadata: {
        "qa_pairs" => { "0" => { "question" => "What time is check-in?", "answer" => "3 PM." } }
      })

      get edit_hotel_knowledge_faq_path(hotel, document), headers: sheet_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What time is check-in?")
      expect(response.body).to include("3 PM.")
    end

    # A fixed card is edited on its own sub-tab. Listing it here as well would
    # give the hotel two places to change one policy.
    it "hides the documents a fixed card owns" do
      GuestContent::SavePolicyDocument.call(hotel, "house_rules", "House Rules", "No parties.")
      create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

      get hotel_knowledge_policies_path(hotel)

      expect(response.body).to include("Parking")
      expect(response.body).not_to include("No parties.")
    end
  end
end
