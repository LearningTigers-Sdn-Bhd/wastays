require "rails_helper"

RSpec.describe Concierge::SendBookingMagicLink do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: nil) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }
  let(:state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:guest) { create(:guest, email: "jasmine@example.com") }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed") }

  before do
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload)
    state.update!(slots_payload: manager.request_existing_booking_code)
    stub_concierge_stylist
  end

  it "sends the existing portal link and stores no booking identity" do
    result = nil

    expect {
      result = described_class.new(
        hotel: hotel,
        conversation: conversation,
        confirmation_token: booking.confirmation_token
      ).call
    }.to have_enqueued_mail(GuestMailer, :magic_link)

    expect(result).to be_success
    task = state.reload.slots_payload["existing_booking_task"]
    expect(task["status"]).to eq("link_sent")
    expect(task).not_to have_key("booking_id")
    expect(conversation.messages.last.body).to include("j•••@example.com")
    expect(conversation.messages.last.body).not_to include(booking.check_in.to_date.to_s, booking.guest_name)
  end

  it "uses one reply for unknown, inactive, and cross-hotel codes" do
    inactive = create(:booking, hotel: hotel, status: "cancelled")
    cross_hotel = create(:booking, hotel: create(:hotel), status: "confirmed")

    replies = [ "missing", inactive.confirmation_token, cross_hotel.confirmation_token ].map do |token|
      state.update!(slots_payload: AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload).request_existing_booking_code)
      described_class.new(hotel: hotel, conversation: conversation, confirmation_token: token).call
      conversation.messages.where(direction: "outbound").last.body
    end

    expect(replies.uniq.one?).to be(true)
  end

  it "offers staff after five failed codes without requesting them automatically" do
    5.times do
      described_class.new(hotel: hotel, conversation: conversation, confirmation_token: "wrong").call
    end

    expect(state.reload.slots_payload.dig("existing_booking_task", "status")).to eq("locked")
    expect(state.slots_payload.dig("ui_task", "suggestion_group")).to eq("magic_link_failure")
    expect(conversation.reload).not_to be_human_requested
  end

  it "offers staff when the booking has no primary guest" do
    booking.booking_guests.update_all(is_primary: false)

    described_class.new(
      hotel: hotel,
      conversation: conversation,
      confirmation_token: booking.confirmation_token
    ).call

    expect(conversation.messages.last.body).to include("hotel team can help you here")
    expect(state.reload.slots_payload.dig("existing_booking_task", "status")).to eq("handoff_offered")
  end

  it "reports the shared cooldown with the masked email" do
    guest.generate_magic_token!

    described_class.new(
      hotel: hotel,
      conversation: conversation,
      confirmation_token: booking.confirmation_token
    ).call

    expect(conversation.messages.last.body).to include("already sent to j•••@example.com", "two minutes")
  end
end
