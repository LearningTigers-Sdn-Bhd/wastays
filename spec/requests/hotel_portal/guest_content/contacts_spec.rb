# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::Contacts", type: :request do
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

  describe "GET the page" do
    it "shows the four sections a hotel has to fill, each with its own form" do
      get hotel_guest_contact_path(hotel)

      expect(response).to have_http_status(:ok)
      headings = response.parsed_body.css("h2").map { |heading| heading.text.squish }
      expect(headings).to include("Front desk", "After hours", "Emergency", "Escalation rules")
      expect(response.parsed_body.css("form[action=\"#{hotel_guest_contact_path(hotel)}\"]").count).to eq(4)
    end

    it "starts every Save switched off, because nothing changed yet" do
      get hotel_guest_contact_path(hotel)

      saves = response.parsed_body.css("button[data-form-dirty-target=\"submit\"]")
      expect(saves.count).to eq(4)
      expect(saves.all? { |button| button[:disabled].present? }).to be(true)
    end
  end

  describe "PATCH the page" do
    it "saves the contacts, the hours, and the escalation rules" do
      patch hotel_guest_contact_path(hotel), params: {
        section: "front-desk",
        hotel_guest_contact: {
          front_desk_phone: "+60 3 1234 5678",
          front_desk_open_24h: "0",
          front_desk_opens_at: "07:00",
          front_desk_closes_at: "23:00",
          duty_manager_phone: "+60 12 987 6543",
          emergency_services_number: "999",
          escalation_triggers: [ "", "complaint" ],
          escalation_attempts: 3
        }
      }

      expect(response).to redirect_to(hotel_guest_contact_path(hotel))
      contact = hotel.reload.guest_contact
      expect(contact.front_desk_phone).to eq("+60 3 1234 5678")
      expect(contact.front_desk_opens_at.strftime("%H:%M")).to eq("07:00")
      expect(contact.duty_manager_phone).to eq("+60 12 987 6543")
      expect(contact.escalation_triggers).to eq([ "complaint" ])
      expect(contact.escalation_attempts).to eq(3)
    end

    it "re-renders with the error when the hours are missing" do
      patch hotel_guest_contact_path(hotel), params: {
        section: "front-desk",
        hotel_guest_contact: { front_desk_open_24h: "0", front_desk_opens_at: "", front_desk_closes_at: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Front desk opens at")
      expect(hotel.reload.guest_contact).to be_nil
    end

    it "leaves the other sections alone when one section saves" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "complaint" ], emergency_phone: "+60 3 1234 5600")

      patch hotel_guest_contact_path(hotel), params: {
        section: "after-hours",
        hotel_guest_contact: { duty_manager_phone: "+60 12 987 6543" }
      }

      contact = hotel.reload.guest_contact
      expect(contact.duty_manager_phone).to eq("+60 12 987 6543")
      expect(contact.escalation_triggers).to eq([ "complaint" ])
      expect(contact.emergency_phone).to eq("+60 3 1234 5600")
    end
  end
end
