# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::PostWebMessage do
  let(:hotel) { create(:hotel) }

  def post(message, prospect_public_id: nil)
    described_class.new(hotel: hotel, message: message, prospect_public_id: prospect_public_id).call
  end

  it "files what the guest typed and hands back the thread it went into" do
    result = post("Do you have parking?")

    expect(result).to be_success
    expect(result.conversation.channel).to eq(described_class::CHANNEL)
    expect(result.conversation.messages.map(&:body)).to eq([ "Do you have parking?" ])
    expect(result.prospect.conversations).to include(result.conversation)
  end

  it "refuses an empty message" do
    result = post("   ")

    expect(result).not_to be_success
    expect(result.error).to be_present
    expect(hotel.prospects.count).to eq(0)
  end

  it "refuses a message longer than the limit" do
    result = post("a" * (described_class::MAX_MESSAGE_LENGTH + 1))

    expect(result).not_to be_success
    expect(hotel.prospects.count).to eq(0)
  end

  it "keeps a returning visitor on the same thread" do
    first = post("Hello")

    second = post("Still there?", prospect_public_id: first.prospect.public_id)

    expect(second.prospect).to eq(first.prospect)
    expect(second.conversation).to eq(first.conversation)
    expect(second.conversation.messages.count).to eq(2)
  end

  it "clears stale suggestions when the guest types a free-form message" do
    first = post("Hello")
    state = create(:prospect_conversation_state, prospect: first.prospect)
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload)
    state.update!(slots_payload: manager.show_suggestions("greeting"))

    post("Tell me about parking", prospect_public_id: first.prospect.public_id)

    expect(state.reload.slots_payload.dig("ui_task", "suggestion_group")).to be_nil
  end

  it "asks the assistant to answer when the hotel has one" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(true)

    expect { post("Do you have parking?") }
      .to have_enqueued_job(Concierge::AnswerWebMessageJob)
  end

  it "files the message without an answer when the hotel has no assistant" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(false)

    result = nil
    expect { result = post("Do you have parking?") }
      .not_to have_enqueued_job(Concierge::AnswerWebMessageJob)
    expect(result.conversation.messages.count).to eq(1)
  end

  it "stays quiet once a person has taken the thread over" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(true)
    first = post("Hello")
    first.conversation.update!(mode: "human")

    expect { post("Anyone there?", prospect_public_id: first.prospect.public_id) }
      .not_to have_enqueued_job(Concierge::AnswerWebMessageJob)
  end
end
