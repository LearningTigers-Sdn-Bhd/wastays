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
      expect(response.body).to include("public-chat__bar")
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

        expect(response.body).to include(Conversation::FRONT_DESK_STATUS)
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

  # The guest should never wait on a model to see their own words. The request
  # files the message; the answer is somebody else's problem.
  describe "when the assistant is answering" do
    before { hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "k") }

    it "files the message in the request and leaves the answer to a job" do
      expect(AiConcierge::Orchestration::Core::InquiryResponder).not_to receive(:new)

      expect {
        post chat_path, params: { message: "Do you have parking?" }
      }.to have_enqueued_job(Concierge::AnswerWebMessageJob)

      expect(Conversation.last.messages.last.body).to eq("Do you have parking?")
    end

    # The assistant is told not to file it again, so this is what proves the two
    # halves do not both write it.
    it "records what the guest typed exactly once" do
      post chat_path, params: { message: "Do you have parking?" }

      expect(ProspectMessage.where(body: "Do you have parking?").count).to eq(1)
    end

    it "shows the guest their own message straight back" do
      post chat_path, params: { message: "Do you have parking?" }
      follow_redirect!

      expect(response.body).to include("Do you have parking?")
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

  # The chat has no page heading at all -- the bar is the only thing naming the
  # hotel, and the names above the bubbles only appear at the start of a run.
  describe "knowing who you are talking to" do
    it "keeps the hotel's name above the thread" do
      get chat_path

      expect(response.body).to include(hotel.name)
      expect(response.body).to include("public-chat__bar-title")
    end

    it "says the front desk answers when the hotel has no assistant" do
      get chat_path

      expect(response.body).to include("Our front desk replies here")
    end

    it "says a person is answering once staff have taken the thread" do
      post chat_path, params: { message: "Do you have parking?" }
      Conversation.last.hand_to_human!

      get chat_path

      expect(response.body).to include("Our front desk is answering you now")
    end
  end

  # Sending should not rebuild the page around the guest. On a phone a reload is
  # a visible flash and a lost keyboard.
  describe "sending without leaving the page" do
    it "answers a send with streams rather than a redirect" do
      post chat_path, params: { message: "Do you have parking?" }, as: :turbo_stream

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include("Do you have parking?")
    end

    # The bar, the box and the guest's place in the thread all survive a send:
    # rebuilding the chat around a message they can already see would close an
    # open menu and drop the keyboard.
    it "adds the message to the thread instead of rebuilding the chat" do
      post chat_path, params: { message: "Do you have parking?" }, as: :turbo_stream

      expect(response.body).to include(%(action="append" target="#{PublicUI::Chat::Log::DEFAULT_ID}"))
      expect(response.body).not_to include("public-chat__bar")
    end

    # The case the subscription element exists for: before the first message
    # there is no thread, so there is nothing for the page to be listening to.
    it "hands a first-time visitor their subscription with their first message" do
      post chat_path, params: { message: "Hello" }, as: :turbo_stream

      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include("Hello")
    end

    it "shows a refusal in place instead of on a reloaded page" do
      post chat_path, params: { message: "" }, as: :turbo_stream

      expect(response.body).to include("concierge-chat-error")
      expect(response.body).to include("Please type a message first")
    end

    it "clears a refusal once the next message is accepted" do
      post chat_path, params: { message: "" }, as: :turbo_stream
      post chat_path, params: { message: "Do you have parking?" }, as: :turbo_stream

      expect(response.body).not_to include("Please type a message first")
    end

    # No JavaScript, no Turbo -- the chat still has to work.
    it "still redirects a browser that asked for HTML" do
      post chat_path, params: { message: "Do you have parking?" }

      # Redirects address the hotel by its canonical unique_id, not the slug the
      # QR code happens to carry.
      expect(response).to redirect_to(concierge_chat_path(hotel))
    end
  end

  describe "DELETE chat" do
    def clear_path = "/concierge/#{hotel.slug}/chat"

    it "puts the guest's thread away and gives them an empty chat" do
      post chat_path, params: { message: "Do you have parking?" }

      delete clear_path
      follow_redirect!

      expect(Conversation.last).not_to be_open
      expect(response.body).not_to include("Do you have parking?")
    end

    # Cleared is not erased: the hotel is still answering the person, and the
    # thread is still on the desk.
    it "leaves the transcript where staff can still read it" do
      post chat_path, params: { message: "Do you have parking?" }

      delete clear_path

      expect(Conversation.last.messages.map(&:body)).to include("Do you have parking?")
    end

    it "starts a fresh thread on the next message, for the same visitor" do
      post chat_path, params: { message: "First thread" }
      delete clear_path

      expect {
        post chat_path, params: { message: "Second thread" }
      }.to change(Conversation, :count).by(1).and change(Prospect, :count).by(0)
    end

    it "is harmless for a visitor who has never written" do
      delete clear_path

      expect(response).to redirect_to(concierge_chat_path(hotel))
    end

    # The menu is the only way to reach it, so it has to be on the page.
    it "offers clearing from the chat itself" do
      get chat_path

      expect(response.body).to include("Clear conversation")
      expect(response.body).to include("public-menu__trigger")
    end
  end

  # The reason the web chat came before WhatsApp: the guest's browser is
  # already connected, so a staff reply reaches them with no integration.
  describe "the live connection" do
    it "subscribes the page to the guest's own thread" do
      post chat_path, params: { message: "Do you have parking?" }
      follow_redirect!

      expect(response.body).to include("turbo-cable-stream-source")
    end

    it "subscribes to nothing before the visitor has a thread" do
      get chat_path

      expect(response.body).not_to include("turbo-cable-stream-source")
    end
  end

  describe "when a person is holding the thread" do
    it "shows the guest who they are talking to" do
      post chat_path, params: { message: "Anyone there?" }
      staff = create(:user, account: hotel.account, name: "Farah Idris")
      Concierge::TakeOverConversation.new(conversation: Conversation.last, user: staff).call

      get chat_path

      expect(response.body).to include("Farah Idris is answering you now")
    end

    it "shows the staff reply as coming from a person, not from the guest" do
      post chat_path, params: { message: "Anyone there?" }
      staff = create(:user, account: hotel.account, name: "Farah Idris")
      Concierge::PostStaffReply.new(conversation: Conversation.last, user: staff, body: "Yes, we have parking.").call

      get chat_path

      expect(response.body).to include("Yes, we have parking.")
      expect(response.body).to include("Farah Idris")
      expect(response.body).to include("has joined this conversation")
    end
  end
end
