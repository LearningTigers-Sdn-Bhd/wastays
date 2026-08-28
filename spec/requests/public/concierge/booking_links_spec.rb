# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public Concierge booking links", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: feature, enabled: true)
    post concierge_chat_messages_path(hotel), params: { message: "Hello" }
    @conversation = Conversation.last
    @state = create(:prospect_conversation_state, prospect: @conversation.prospect)
  end

  it "shows a secure confirmation-code field while a link request is pending" do
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: @state.slots_payload)
    @state.update!(slots_payload: manager.request_existing_booking_code)

    get concierge_chat_path(hotel)

    expect(response.body).to include("Booking confirmation code")
    expect(response.body).not_to include("Type your message")
  end

  it "sends a portal link without recording the code or exposing booking facts" do
    booking = booking_with_primary_guest
    request_confirmation_code

    expect {
      post concierge_chat_booking_path(hotel),
        params: { confirmation_token: booking.confirmation_token },
        headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to have_enqueued_mail(GuestMailer, :magic_link)

    expect(ProspectMessage.where(body: booking.confirmation_token)).not_to exist
    expect(@state.reload.slots_payload.dig("existing_booking_task", "status")).to eq("link_sent")
    reply = @conversation.messages.where(direction: "outbound").last.body
    expect(reply).to include("secure login link", "Ready to plan your next stay?")
    expect(reply).not_to include(booking.check_in.to_date.to_s, booking.guest_name, booking.guest_email)
    expect(response.body).to include(PublicUI::Chat::Panel::INPUT_REGION_ID, "Find a room", "Type your message")
  end

  it "keeps an invalid code out of history and keeps the secure field active" do
    request_confirmation_code

    post concierge_chat_booking_path(hotel),
      params: { confirmation_token: "wrong" },
      headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(ProspectMessage.where(body: "wrong")).not_to exist
    expect(response.body).to include("Booking confirmation code")
    expect(@state.reload.slots_payload.dig("existing_booking_task", "status")).to eq("awaiting_confirmation_code")
  end

  it "does not let another browser submit a code for this conversation" do
    request_confirmation_code
    other_browser = open_session

    other_browser.post concierge_chat_booking_path(hotel), params: { confirmation_token: "anything" }

    expect(other_browser.response).to have_http_status(:not_found)
  end

  it "does not carry secure input into a new conversation" do
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: @state.slots_payload)
    @state.update!(slots_payload: manager.request_existing_booking_code(conversation_id: @conversation.id))
    Concierge::ClearConversation.new(conversation: @conversation).call

    post concierge_chat_messages_path(hotel), params: { message: "Hello again" }
    get concierge_chat_path(hotel)

    expect(response.body).to include("Type your message")
    expect(response.body).not_to include("Booking confirmation code")
  end

  private

  def request_confirmation_code
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: @state.slots_payload)
    @state.update!(slots_payload: manager.request_existing_booking_code)
  end

  def booking_with_primary_guest
    booking = create(:booking, hotel: hotel, status: "confirmed")
    create(:booking_guest, booking: booking, guest: create(:guest, email: "jasmine@example.com"), is_primary: true)
    booking
  end
end
