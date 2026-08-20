# frozen_string_literal: true

require "rails_helper"

# ScriptedChat, which every eval fixture runs through, defines
# `with_instructions(*) = self` -- it swallows both the text and the keyword.
# So no fixture can ever catch the prompt arriving as one block again. This
# needs a double of its own.
RSpec.describe AiConcierge::Orchestration::AgentLoop::BuildChat do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:recorder) { AiConcierge::Orchestration::AgentLoop::ToolRecorder.new }
  let(:chat) { instance_double(RubyLLM::Chat).as_null_object }

  def build
    context = AiConcierge::Orchestration::AgentLoop::TurnContext.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: "hi"
    )
    described_class.new(context: context, tools: [], recorder: recorder, max_hops: 4).call
  end

  before do
    allow(AiConcierge::Providers::RubyLlmClient).to receive(:new).and_return(
      instance_double(AiConcierge::Providers::RubyLlmClient, chat: chat, cacheable: "STABLE")
    )
  end

  # The cache breakpoint is a boundary between blocks, so there have to be two.
  it "sends the instructions as a cacheable block and a turn block after it" do
    build

    expect(chat).to have_received(:with_instructions).with("STABLE").ordered
    expect(chat).to have_received(:with_instructions)
      .with(a_string_including(Date.current.iso8601), append: true).ordered
  end
end
