# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Concierge::Chats", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  def chat_path = "/concierge/#{hotel.slug}/chat"

  describe "GET chat" do
    it "opens for a visitor who has never written before" do
      get chat_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Ask us")
    end

    it "creates nothing until the visitor actually says something" do
      expect { get chat_path }.not_to change(Prospect, :count)
    end
  end

  describe "POST chat" do
    context "when the hotel has no AI provider configured" do
      it "still records the message so the front desk can answer it" do
        expect {
          post chat_path, params: { message: "Do you have parking?" }
        }.to change(Prospect, :count).by(1).and change(Conversation, :count).by(1)

        message = ProspectMessage.last
        expect(message.body).to eq("Do you have parking?")
        expect(message.sender_role).to eq("guest")
        expect(message.conversation.channel).to eq("web")
      end

      it "tells the visitor a person will reply" do
        post chat_path, params: { message: "Do you have parking?" }
        follow_redirect!

        expect(response.body).to include("straight to our front desk")
      end

      it "keeps the same thread on the visitor's next message" do
        post chat_path, params: { message: "First question" }
        post chat_path, params: { message: "Second question" }

        expect(Conversation.count).to eq(1)
        expect(Conversation.last.messages.count).to eq(2)
      end

      it "shows the visitor their own history when they come back" do
        post chat_path, params: { message: "Do you have parking?" }

        get chat_path

        expect(response.body).to include("Do you have parking?")
      end

      # The point of the whole phase: what a guest types on the public page has
      # to turn up on the desk a staff member is watching.
      it "puts the thread in front of staff in the portal inbox" do
        post chat_path, params: { message: "Do you have parking?" }

        inbox = HotelPortal::ConversationsQuery.new(hotel: hotel).call

        expect(inbox).to include(Conversation.last)
        expect(Conversation.last.messages.first.body).to eq("Do you have parking?")
      end

      it "does not show one visitor another visitor's thread" do
        post chat_path, params: { message: "My private question" }

        other_browser = open_session
        other_browser.get chat_path

        expect(other_browser.response.body).not_to include("My private question")
      end
    end

    it "refuses an empty message without creating anything" do
      expect {
        post chat_path, params: { message: "   " }
      }.not_to change(Prospect, :count)

      follow_redirect!
      expect(response.body).to include("Please type a message first")
    end

    it "refuses a message longer than the limit" do
      post chat_path, params: { message: "a" * 2_001 }
      follow_redirect!

      expect(response.body).to include("too long")
      expect(ProspectMessage.count).to eq(0)
    end
  end

  describe "when staff have taken the thread over" do
    it "records the guest's message without the bot answering" do
      post chat_path, params: { message: "First" }
      conversation = Conversation.last
      conversation.hand_to_human!
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "k")

      expect(AiConcierge::Orchestration::Core::InquiryResponder).not_to receive(:new)

      post chat_path, params: { message: "Anyone there?" }

      expect(conversation.reload.messages.last.body).to eq("Anyone there?")
    end
  end
end
