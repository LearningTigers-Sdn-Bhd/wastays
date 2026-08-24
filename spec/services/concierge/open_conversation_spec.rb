require "rails_helper"

RSpec.describe Concierge::OpenConversation do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }

  def open_thread(channel: "web") = described_class.new(prospect: prospect, channel: channel).call

  it "continues the thread the guest is still in" do
    first = open_thread

    expect(open_thread).to eq(first)
    expect(prospect.conversations.count).to eq(1)
  end

  it "opens a new thread once the previous one is closed" do
    first = open_thread
    first.close!

    second = open_thread

    expect(second).not_to eq(first)
    expect(second).to be_open
  end

  it "keeps channels apart" do
    web = open_thread(channel: "web")
    whatsapp = open_thread(channel: "whatsapp")

    expect(whatsapp).not_to eq(web)
  end

  # The bug this guards: state is keyed to the prospect, so the question the
  # closed thread was waiting on outlived it, and the first message of the new
  # chat was answered as an option selection.
  it "starts the assistant over when a new thread is opened" do
    create(:conversation, :closed, hotel: hotel, prospect: prospect, channel: "web")
    state = create(:prospect_conversation_state, :awaiting_option_selection, prospect: prospect, flow_status: "paused")

    open_thread

    state.reload
    expect(state.pending_question).to be_nil
    expect(state.active_topic).to be_nil
    expect(state.active_flow).to be_nil
    expect(state.slots_payload).to eq({})
    expect(state.flow_status).to eq("active")
  end

  it "leaves the state alone while the same thread continues" do
    create(:conversation, hotel: hotel, prospect: prospect, channel: "web")
    state = create(:prospect_conversation_state, :awaiting_option_selection, prospect: prospect)

    open_thread

    expect(state.reload.pending_question).to eq("select_option")
  end

  it "leaves a state alone on the guest's very first thread" do
    state = create(:prospect_conversation_state, :awaiting_option_selection, prospect: prospect)

    open_thread

    expect(state.reload.pending_question).to eq("select_option")
  end

  it "does not need the state to exist yet" do
    create(:conversation, :closed, hotel: hotel, prospect: prospect, channel: "web")

    expect { open_thread }.not_to raise_error
  end
end
