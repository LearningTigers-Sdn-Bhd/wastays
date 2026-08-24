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

  def build(conversation: nil)
    context = AiConcierge::Orchestration::AgentLoop::TurnContext.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: "hi",
      conversation: conversation
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

  it "adds no messages when there is no thread to read" do
    build

    expect(chat).not_to have_received(:add_message)
  end

  # After the instructions, because the providers cache a prefix of tools +
  # system and a message moving above that line would cost every hotel its
  # cache. Before the current message, which Chat#ask appends itself.
  it "seeds the thread after the instructions, oldest first" do
    conversation = create(:conversation, hotel: hotel, prospect: prospect)
    create(:prospect_message, prospect: prospect, conversation: conversation,
                              body: "do you have a pool", direction: "inbound",
                              sender_role: "guest", sent_at: 2.minutes.ago)
    create(:prospect_message, prospect: prospect, conversation: conversation,
                              body: "Yes, on the roof.", direction: "outbound",
                              sender_role: "bot", sent_at: 1.minute.ago)

    build(conversation: conversation)

    expect(chat).to have_received(:with_instructions).with("STABLE").ordered
    expect(chat).to have_received(:add_message)
      .with(role: :user, content: "do you have a pool").ordered
    expect(chat).to have_received(:add_message)
      .with(role: :assistant, content: "Yes, on the roof.").ordered
  end
end
