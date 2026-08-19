# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Conversations", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_concierge) do
    Permission.find_or_create_by!(slug: "manage_concierge") { |permission| permission.name = "Manage Concierge" }
  end

  before do
    role.permissions << manage_concierge
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def conversation_for(target_hotel, name:, **attributes)
    prospect = create(:prospect, hotel: target_hotel, name: name)
    create(:conversation, hotel: target_hotel, prospect: prospect, **attributes)
  end

  describe "GET index" do
    it "lists this hotel's conversations and nobody else's" do
      conversation_for(hotel, name: "Aisyah Rahman")
      conversation_for(other_hotel, name: "Someone Elses Guest")

      get hotel_conversations_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Aisyah Rahman")
      expect(response.body).not_to include("Someone Elses Guest")
    end

    it "shows open threads by default and hides closed ones" do
      conversation_for(hotel, name: "Still Talking")
      conversation_for(hotel, name: "Long Finished", status: "closed", closed_at: Time.current)

      get hotel_conversations_path(hotel)

      expect(response.body).to include("Still Talking")
      expect(response.body).not_to include("Long Finished")
    end

    it "shows closed threads when asked for them" do
      conversation_for(hotel, name: "Long Finished", status: "closed", closed_at: Time.current)

      get hotel_conversations_path(hotel, status: "closed")

      expect(response.body).to include("Long Finished")
    end

    it "narrows to the threads a person has been handed" do
      conversation_for(hotel, name: "Needs A Human", mode: "human")
      conversation_for(hotel, name: "Bot Is Coping")

      get hotel_conversations_path(hotel, filter: "awaiting_staff")

      expect(response.body).to include("Needs A Human")
      expect(response.body).not_to include("Bot Is Coping")
    end

    it "searches by guest name" do
      conversation_for(hotel, name: "Nurul Huda")
      conversation_for(hotel, name: "Someone Different")

      get hotel_conversations_path(hotel, q: "nurul")

      expect(response.body).to include("Nurul Huda")
      expect(response.body).not_to include("Someone Different")
    end

    it "refuses a user without the concierge permission" do
      role.permissions.destroy_all

      get hotel_conversations_path(hotel)

      expect(response).not_to have_http_status(:success)
    end
  end

  describe "GET show" do
    it "renders the thread with both sides of the exchange" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")
      create(:prospect_message, prospect: conversation.prospect, conversation: conversation,
                                direction: "inbound", body: "Do you have a sea view room?")
      create(:prospect_message, prospect: conversation.prospect, conversation: conversation,
                                direction: "outbound", body: "Yes, we have two available.")

      get hotel_conversation_path(hotel, conversation)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Do you have a sea view room?")
      expect(response.body).to include("Yes, we have two available.")
      expect(response.body).to include("Assistant")
    end

    it "marks the guest's messages read once staff have opened the thread" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")
      guest_message = create(:prospect_message, prospect: conversation.prospect, conversation: conversation,
                                                direction: "inbound", body: "Hello?")

      expect { get hotel_conversation_path(hotel, conversation) }
        .to change { guest_message.reload.read_at }.from(nil)
    end

    it "does not open another hotel's conversation" do
      conversation = conversation_for(other_hotel, name: "Someone Elses Guest")

      get hotel_conversation_path(hotel, conversation)

      expect(response).to redirect_to(hotel_conversations_path(hotel))
    end
  end
end
