# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::Policies", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

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
  end

  describe "Other Policies" do
    it "lists the policies a hotel named itself" do
      create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

      get hotel_knowledge_policies_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Parking")
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
