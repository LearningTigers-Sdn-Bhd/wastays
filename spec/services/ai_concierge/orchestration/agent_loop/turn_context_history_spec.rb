# frozen_string_literal: true

require "rails_helper"

# What the model is allowed to read of the thread it is answering in.
#
# The selection is the whole of it: everything else in TurnContext is a fact
# from Postgres, and this is the one place the model is handed prose it might
# read differently from the columns. Kept deliberately small and deliberately
# behind the current message.
RSpec.describe AiConcierge::Orchestration::AgentLoop::TurnContext do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  def say(body, direction:, sender_role:, at:)
    create(:prospect_message,
           prospect: prospect, conversation: conversation, body: body,
           direction: direction, sender_role: sender_role, sent_at: at)
  end

  def guest(body, at:) = say(body, direction: "inbound", sender_role: "guest", at: at)
  def bot(body, at:) = say(body, direction: "outbound", sender_role: "bot", at: at)

  def context_for(message, conversation: self.conversation)
    described_class.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: message,
      conversation: conversation
    )
  end

  it "is empty when there is no thread to read" do
    expect(context_for("hi", conversation: nil).recent_messages).to eq([])
  end

  # Both channels file the guest's message before the loop runs, and
  # RubyLLM::Chat#ask adds it again as the user turn.
  it "leaves out the message being answered" do
    guest("do you have a pool", at: 3.minutes.ago)
    bot("Yes, on the roof.", at: 2.minutes.ago)
    guest("what time does it open", at: 1.minute.ago)

    expect(context_for("what time does it open").recent_messages).to eq(
      [
        { role: :user, content: "do you have a pool" },
        { role: :assistant, content: "Yes, on the roof." }
      ]
    )
  end

  it "reads the hotel's side as the assistant whether a bot or a person wrote it" do
    bot("Yes, on the roof.", at: 3.minutes.ago)
    say("Sorry, it is closed today.", direction: "outbound", sender_role: "staff", at: 2.minutes.ago)

    expect(context_for("thanks").recent_messages.map { _1[:role] }).to eq(%i[assistant assistant])
  end

  # "Nurah has joined the conversation" is chrome, not something the guest said
  # or the hotel answered.
  it "leaves out the handover notices" do
    guest("can someone help", at: 3.minutes.ago)
    say("Nurah has joined.", direction: "system", sender_role: "system", at: 2.minutes.ago)

    expect(context_for("hello").recent_messages).to eq([ { role: :user, content: "can someone help" } ])
  end

  it "carries only the last few turns, oldest first" do
    10.times { |index| guest("message #{index}", at: (20 - index).minutes.ago) }

    contents = context_for("latest").recent_messages.map { _1[:content] }

    expect(contents.length).to eq(described_class::HISTORY_LIMIT)
    expect(contents.first).to eq("message 4")
    expect(contents.last).to eq("message 9")
  end

  # A catalogue reply is the longest thing in a thread; which row the guest
  # meant is answered from Postgres, not by re-reading the list.
  it "trims a long reply rather than letting one turn set the bill" do
    bot("x" * 900, at: 1.minute.ago)

    content = context_for("hi").recent_messages.sole[:content]

    expect(content.length).to eq(described_class::MAX_HISTORY_BODY)
  end
end
