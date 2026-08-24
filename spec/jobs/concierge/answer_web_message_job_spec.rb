# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::AnswerWebMessageJob do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web", mode: "bot", status: "open") }

  let(:responder) { instance_double(AiConcierge::Orchestration::Core::InquiryResponder) }

  before { allow(hotel).to receive(:ai_concierge_ready?).and_return(true) }

  def stub_responder(success: true, error: nil)
    allow(AiConcierge::Orchestration::Core::InquiryResponder).to receive(:new).and_return(responder)
    allow(responder).to receive(:call).and_return(
      if success
        AiConcierge::Orchestration::Core::Result.success(payload: { message: "Yes, free parking." })
      else
        AiConcierge::Orchestration::Core::Result.failure(error: error, status: :internal_server_error)
      end
    )
  end

  def perform(message: "Do you have parking?")
    described_class.new.perform(conversation.id, message)
  end

  context "when the assistant is still holding the conversation" do
    before do
      allow(Hotel).to receive(:find_by).and_call_original
      allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(true)
    end

    it "asks the assistant without filing the guest's message again" do
      stub_responder

      expect(AiConcierge::Orchestration::Core::InquiryResponder).to receive(:new)
        .with(hash_including(record_inbound: false, message: "Do you have parking?", channel: "web"))
        .and_return(responder)

      perform
    end

    # Silence reads as the hotel ignoring them.
    it "tells the guest when the assistant could not answer" do
      stub_responder(success: false, error: "AI Concierge is temporarily unavailable.")

      expect { perform }.to change { conversation.messages.count }.by(1)
      expect(conversation.messages.last.sender_role).to eq("system")
      expect(conversation.messages.last.body).to eq(described_class::UNAVAILABLE_NOTICE)
    end

    it "says nothing extra when the assistant answered" do
      stub_responder

      expect { perform }.not_to change { conversation.messages.count }
    end
  end

  # The window between the guest pressing Send and this running is exactly when
  # a staff member takes the thread over.
  it "stays quiet when a person has taken the conversation over" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(true)
    conversation.hand_to_human!(user: create(:user, account: hotel.account))

    expect(AiConcierge::Orchestration::Core::InquiryResponder).not_to receive(:new)

    expect { perform }.not_to change { conversation.messages.count }
  end

  it "stays quiet on a conversation that was closed in the meantime" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(true)
    conversation.close!

    expect(AiConcierge::Orchestration::Core::InquiryResponder).not_to receive(:new)

    perform
  end

  it "stays quiet when the hotel has no assistant configured" do
    allow_any_instance_of(Hotel).to receive(:ai_concierge_ready?).and_return(false)

    expect(AiConcierge::Orchestration::Core::InquiryResponder).not_to receive(:new)

    perform
  end

  # A conversation deleted between enqueue and run must not take the queue down.
  it "does nothing for a conversation that is gone" do
    expect { described_class.new.perform(-1, "Hello") }.not_to raise_error
  end
end
