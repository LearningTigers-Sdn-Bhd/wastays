# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::CloseStaleConversations do
  let(:hotel) { create(:hotel) }
  let(:stale_at) { described_class::STALE_AFTER.ago - 1.hour }

  def thread(last_message_at:, hotel: self.hotel, with_message: true, **attributes)
    prospect = create(:prospect, hotel: hotel)
    conversation = create(:conversation, hotel: hotel, prospect: prospect, **attributes)
    create(:prospect_message, conversation: conversation, prospect: prospect) if with_message
    conversation.update_columns(last_message_at: last_message_at)
    conversation
  end

  it "closes a thread nobody has said anything on for days" do
    conversation = thread(last_message_at: stale_at)

    expect(described_class.new.call).to eq(1)
    expect(conversation.reload).not_to be_open
    expect(conversation.closed_at).to be_present
  end

  it "leaves a thread that is still being talked on" do
    conversation = thread(last_message_at: 2.hours.ago)

    expect(described_class.new.call).to eq(0)
    expect(conversation.reload).to be_open
  end

  it "leaves a thread that is already closed" do
    conversation = thread(last_message_at: stale_at, status: "closed")
    closed_at = conversation.closed_at

    described_class.new.call

    expect(conversation.reload.closed_at).to eq(closed_at)
  end

  # The user's call: one horizon for every thread. A three-day-old enquiry
  # cannot be answered on WhatsApp anyway, and staff keep the transcript.
  it "closes a thread waiting on a person like any other" do
    conversation = thread(last_message_at: stale_at, mode: "human", human_requested_at: 4.days.ago)

    described_class.new.call

    expect(conversation.reload).not_to be_open
  end

  # Otherwise an empty row sits holding the person's one open slot on that
  # channel, and their next message resumes a thread that never began.
  it "closes an empty thread on when it was opened" do
    conversation = thread(last_message_at: nil, with_message: false)
    conversation.update_columns(created_at: stale_at)

    described_class.new.call

    expect(conversation.reload).not_to be_open
  end

  describe "what it leaves behind" do
    it "says in the transcript why the thread stops" do
      conversation = thread(last_message_at: stale_at)

      described_class.new.call

      expect(conversation.messages.reload.last.body).to eq(described_class::CLOSING_NOTE)
      expect(conversation.messages.last.sender_role).to eq("system")
    end

    # Nothing to explain, and the note would be the row's first message, which
    # announces its arrival to the inbox a moment before it closes.
    it "says nothing on a thread that never had a word in it" do
      conversation = thread(last_message_at: nil, with_message: false)
      conversation.update_columns(created_at: stale_at)

      described_class.new.call

      expect(conversation.messages.reload).to be_empty
    end

    # A closing note is not the hotel talking to the guest.
    it "sends nothing to the guest's channel" do
      thread(last_message_at: stale_at, channel: "whatsapp")

      expect { described_class.new.call }.not_to have_enqueued_job(WebhookBroadcastJob)
    end
  end

  describe "working in batches" do
    it "stops at the limit and takes the oldest first" do
      oldest = thread(last_message_at: 30.days.ago)
      thread(last_message_at: stale_at)

      expect(described_class.new(limit: 1).call).to eq(1)
      expect(oldest.reload).not_to be_open
    end

    # Each close pushes its own row, but the tab counts are a fact about the
    # hotel: fifty closes must not mean fifty count queries and fifty pushes.
    it "sends the tab counts once per hotel, not once per thread" do
      3.times { thread(last_message_at: stale_at) }
      allow(Conversation).to receive(:broadcast_counts_to_inbox)

      described_class.new.call

      expect(Conversation).to have_received(:broadcast_counts_to_inbox).with(hotel).once
    end

    it "sends them for each hotel it touched" do
      other_hotel = create(:hotel)
      thread(last_message_at: stale_at)
      thread(last_message_at: stale_at, hotel: other_hotel)
      allow(Conversation).to receive(:broadcast_counts_to_inbox)

      described_class.new.call

      expect(Conversation).to have_received(:broadcast_counts_to_inbox).twice
    end
  end

  # One bad row must not take the rest of the batch with it.
  it "carries on after a thread it cannot close" do
    failing = thread(last_message_at: stale_at)
    healthy = thread(last_message_at: stale_at)
    allow_any_instance_of(Conversation).to receive(:close!).and_wrap_original do |method, *args, **kwargs|
      raise ActiveRecord::RecordInvalid.new(failing) if method.receiver.id == failing.id

      method.call(*args, **kwargs)
    end

    described_class.new.call

    expect(healthy.reload).not_to be_open
    expect(failing.reload).to be_open
  end
end
