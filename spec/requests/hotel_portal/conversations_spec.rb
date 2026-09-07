# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Conversations", type: :request do
  # The inbox is the staff end of the guest chat, so it is gated on exactly what
  # the chat is gated on: the hotel has the concierge page, and its plan carries
  # the feature. Without both, a guest cannot open a thread for staff to answer.
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:other_hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_concierge) do
    Permission.find_or_create_by!(slug: "manage_concierge") { |permission| permission.name = "Manage Concierge" }
  end

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
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
      expect(response.parsed_body.at_css("nav.panel-pagination")).to be_nil
    end

    it "paginates filtered conversations at 30 with stable ordering and complete counts" do
      timestamp = Time.zone.local(2026, 9, 7, 9)
      conversations = 31.times.map do |index|
        conversation_for(
          hotel,
          name: "Paged Guest #{index}",
          mode: "human",
          last_message_at: timestamp,
          created_at: timestamp,
          updated_at: timestamp
        )
      end
      params = { filter: "awaiting_staff", q: "Paged Guest" }

      get hotel_conversations_path(hotel), params: params

      page = Capybara.string(response.body)
      pagination = page.find('nav.panel-pagination[aria-label="Conversation pagination"]')
      page_two = pagination.find('a[aria-label="Page 2"]')
      page_two_query = Rack::Utils.parse_nested_query(URI.parse(page_two[:href]).query)
      expect(page).to have_css("#conversation-rows > li", count: 30)
      expect(page).to have_css("#conversation-count-open", text: "31")
      expect(page).to have_text(conversations.last.prospect.name)
      expect(page).to have_no_text(conversations.first.prospect.name)
      expect(page_two_query).to include(params.stringify_keys.merge("page" => "2"))

      get hotel_conversations_path(hotel), params: params.merge(page: 2)

      page = Capybara.string(response.body)
      pagination = page.find("nav.panel-pagination")
      expect(page).to have_css("#conversation-rows > li", count: 1)
      expect(page).to have_text(conversations.first.prospect.name)
      expect(pagination).to have_css('[aria-current="page"]', text: "2")
      expect(pagination).to have_css('a[aria-label="Previous page"]')

      [ "invalid", "0", "-2" ].each do |invalid_page|
        get hotel_conversations_path(hotel), params: params.merge(page: invalid_page)
        expect(Capybara.string(response.body)).to have_css("#conversation-rows > li", count: 30)
      end

      get hotel_conversations_path(hotel), params: params.merge(page: 99)

      page = Capybara.string(response.body)
      expect(page).to have_no_css("#conversation-rows > li")
      expect(page).to have_css('nav.panel-pagination a[aria-label="Previous page"]')
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

    it "keeps the selected thread and filters in pagination links" do
      selected = conversation_for(hotel, name: "Selected Guest", mode: "human")
      30.times do |index|
        conversation_for(hotel, name: "Filtered Guest #{index}", mode: "human")
      end
      params = { filter: "awaiting_staff", q: "Guest", page: 2 }

      get hotel_conversation_path(hotel, selected), params: params

      page = Capybara.string(response.body)
      previous_link = page.find('nav.panel-pagination a[aria-label="Previous page"]')
      uri = URI.parse(previous_link[:href])
      expect(uri.path).to eq(hotel_conversation_path(hotel, selected))
      expect(Rack::Utils.parse_nested_query(uri.query)).to include(
        "filter" => "awaiting_staff",
        "q" => "Guest",
        "page" => "1"
      )
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

  describe "POST reply" do
    it "sends the reply to the guest and takes the thread over" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Yes, we have parking." }

      expect(response).to redirect_to(hotel_conversation_path(hotel, conversation))
      expect(conversation.reload).to be_human
      expect(conversation.assigned_user).to eq(user)
      expect(conversation.messages.last.body).to eq("Yes, we have parking.")
    end

    it "shows the thread with the reply in it afterwards" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Yes, we have parking." }
      follow_redirect!

      expect(response.body).to include("Yes, we have parking.")
    end

    it "reports a refusal instead of pretending the guest was answered" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman", channel: "whatsapp")

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Yes, we have parking." }
      follow_redirect!

      expect(response.body).to include("would not reach the guest")
      expect(conversation.messages.reload).to be_empty
    end

    # The reply was filed, the guest never got it, and taking the thread muted
    # the bot that could still have answered them.
    it "reports a lapsed WhatsApp window instead of filing a reply nobody sends" do
      create(:webhook_endpoint, hotel: hotel, event_types: [ Concierge::DeliverStaffReply::EVENT ])
      prospect = create(:prospect, hotel: hotel, name: "Aisyah Rahman", phone_number: "+60123456789")
      conversation = create(
        :conversation, :whatsapp, hotel: hotel, prospect: prospect,
        last_guest_message_at: Conversation::REPLY_WINDOW.ago - 1.minute
      )

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Sorry for the wait." }
      follow_redirect!

      expect(response.body).to include("24 hours")
      expect(conversation.messages.reload).to be_empty
      expect(conversation.reload).not_to be_human
    end

    it "refuses a user without the concierge permission" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")
      role.permissions.destroy_all

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Hello" }

      expect(conversation.messages.reload).to be_empty
    end

    it "does not reply into another hotel's conversation" do
      conversation = conversation_for(other_hotel, name: "Someone Elses Guest")

      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Hello" }

      expect(response).to redirect_to(hotel_conversations_path(hotel))
      expect(conversation.messages.reload).to be_empty
    end
  end

  describe "changing who answers" do
    it "hands the thread to the person who asked for it" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")

      patch take_over_hotel_conversation_path(hotel, conversation)

      expect(conversation.reload).to be_human
      expect(conversation.assigned_user).to eq(user)
    end

    it "hands it back to the assistant when there is one" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "k")
      conversation = conversation_for(hotel, name: "Aisyah Rahman", mode: "human", assigned_user: user)

      patch return_to_bot_hotel_conversation_path(hotel, conversation)

      expect(conversation.reload).to be_bot
    end

    it "refuses to hand it back to an assistant the hotel does not have" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman", mode: "human", assigned_user: user)

      patch return_to_bot_hotel_conversation_path(hotel, conversation)
      follow_redirect!

      expect(conversation.reload).to be_human
      expect(response.body).to include("not switched on")
    end

    it "closes and reopens a thread" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")

      patch close_hotel_conversation_path(hotel, conversation)
      expect(conversation.reload).not_to be_open

      patch reopen_hotel_conversation_path(hotel, conversation)
      expect(conversation.reload).to be_open
      expect(conversation.closed_at).to be_nil
    end
  end

  describe "the reply box" do
    it "is offered on a thread a reply can actually reach" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")

      get hotel_conversation_path(hotel, conversation)

      expect(response.body).to include("Send reply")
    end

    it "is withheld where nothing would be delivered" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman", channel: "whatsapp")

      get hotel_conversation_path(hotel, conversation)

      expect(response.body).not_to include("Send reply")
      expect(response.body).to include("would not reach the guest")
    end

    it "is withheld on a closed thread" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman", status: "closed", closed_at: Time.current)

      get hotel_conversation_path(hotel, conversation, status: "closed")

      expect(response.body).not_to include("Send reply")
      expect(response.body).to include("Reopen")
    end
  end

  # Replying should not rebuild the inbox around one new bubble -- the reader
  # loses their scroll position and anything half-typed.
  describe "acting on a thread without reloading it" do
    let(:conversation) { conversation_for(hotel, name: "Aisyah Rahman", channel: "web", mode: "bot", status: "open") }

    it "answers a reply with streams rather than a redirect" do
      post reply_hotel_conversation_path(hotel, conversation),
           params: { body: "Yes, we have parking." }, as: :turbo_stream

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    end

    # What a broadcast cannot know is which reader did it. Replying takes the
    # thread over, so the strip that offered "Take over" has to stop offering it.
    it "replaces the parts of the card that now say something different" do
      post reply_hotel_conversation_path(hotel, conversation),
           params: { body: "Yes, we have parking." }, as: :turbo_stream

      expect(response.body).to include(HotelPortal::Inbox::ModeBar.dom_id_for(conversation))
      expect(response.body).to include(HotelPortal::Inbox::Composer.dom_id_for(conversation))
      expect(response.body).to include(HotelPortal::Inbox::ListItem.dom_id_for(conversation))
      expect(response.body).to include("A person is holding this conversation")
      expect(response.body).not_to include("Take over")
    end

    # It is already on its way down the staff stream; sending it twice is what
    # the chat controller's duplicate check has to clean up after.
    it "leaves the message itself to the broadcast" do
      post reply_hotel_conversation_path(hotel, conversation),
           params: { body: "Yes, we have parking." }, as: :turbo_stream

      expect(response.body).not_to include("Yes, we have parking.")
    end

    it "swaps the box for the closed notice when the thread is closed" do
      patch close_hotel_conversation_path(hotel, conversation), as: :turbo_stream

      expect(response.body).to include("Reopen it to reply")
      expect(response.body).not_to include("Send reply")
    end

    it "reports a refusal as a toast instead of a reloaded page" do
      conversation.close!

      post reply_hotel_conversation_path(hotel, conversation),
           params: { body: "Too late." }, as: :turbo_stream

      expect(response.body).to include("Reopen it to reply")
    end

    it "still redirects a browser that asked for HTML" do
      post reply_hotel_conversation_path(hotel, conversation), params: { body: "Yes." }

      expect(response).to redirect_to(hotel_conversation_path(hotel, conversation))
    end
  end

  # Permission says whether this user may read the inbox. These say whether the
  # hotel has an inbox at all -- a different question, and previously nobody
  # asked it: the tab and every URL under it stayed reachable for a hotel whose
  # guests had no chat to write into.
  describe "a hotel without the concierge chat" do
    it "sends the inbox away when the hotel has the concierge page switched off" do
      hotel.update!(concierge_enabled: false)

      get hotel_conversations_path(hotel)

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
      expect(flash[:alert]).to eq("Conversations are not available for this hotel.")
    end

    it "sends the inbox away when the plan does not carry the feature" do
      PlanFeature.find_by!(plan: plan, feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_conversations_path(hotel)

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
    end

    it "closes the individual thread too, not just the list" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman")
      hotel.update!(concierge_enabled: false)

      get hotel_conversation_path(hotel, conversation)

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
    end

    # The writes are the half that matters: a redirect on the list is cosmetic,
    # but a reply filed into a hotel with no chat is a message no guest reads.
    it "refuses a reply rather than filing one nobody can receive" do
      conversation = conversation_for(hotel, name: "Aisyah Rahman", channel: "web")
      hotel.update!(concierge_enabled: false)

      expect do
        post reply_hotel_conversation_path(hotel, conversation), params: { body: "Hello?" }
      end.not_to change(ProspectMessage, :count)

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
    end
  end
end
