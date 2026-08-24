# frozen_string_literal: true

require "rails_helper"

# The inbox as everybody else has it open. A staff member who is not the one
# acting should not have to reload to find out a guest is waiting.
RSpec.describe "Conversation inbox broadcasts", type: :model do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel, name: "Aisyah Rahman") }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web", mode: "bot", status: "open") }

  def inbox_payloads = turbo_broadcasts_to(hotel, :conversations).join

  def write(body: "Do you have parking?", role: "guest")
    create(:prospect_message,
           prospect: prospect,
           conversation: conversation,
           direction: role == "guest" ? "inbound" : "outbound",
           sender_role: role,
           body: body)
  end

  describe "when a message arrives" do
    it "refreshes the row for everyone watching the inbox" do
      conversation
      write

      expect(inbox_payloads).to include(HotelPortal::Inbox::ListItem.dom_id_for(conversation))
      expect(inbox_payloads).to include("Aisyah Rahman")
    end

    # Which thread a reader has open is true for them and nobody else, and it
    # lives on the row itself -- so a broadcast must not replace the row.
    it "updates what the row says without replacing the row" do
      conversation
      write

      payloads = turbo_broadcasts_to(hotel, :conversations)
      row = payloads.find { |p| p.include?(HotelPortal::Inbox::ListItem.dom_id_for(conversation)) }

      expect(row).to include('action="update"')
      expect(row).not_to include('action="replace"')
    end

    it "refreshes the tab counts, which are facts about the whole hotel" do
      conversation
      write

      expect(inbox_payloads).to include("conversation-count-open")
      expect(inbox_payloads).to include("conversation-count-unread")
      expect(inbox_payloads).to include("conversation-count-awaiting_staff")
    end
  end

  describe "when a guest writes in for the first time" do
    it "drops the new thread at the top of the open list" do
      conversation
      write

      arrival = turbo_broadcasts_to(hotel, :conversations, "all").join

      expect(arrival).to include('action="prepend"')
      expect(arrival).to include("conversation-rows")
      expect(arrival).to include("Aisyah Rahman")
    end

    it "also puts it in front of somebody filtered to unread" do
      conversation
      write

      expect(turbo_broadcasts_to(hotel, :conversations, "unread").join).to include('action="prepend"')
    end

    # Somebody reading finished threads should not watch new enquiries drop into
    # the list.
    it "keeps it away from somebody filtered to closed threads" do
      conversation
      write

      expect(turbo_broadcasts_to(hotel, :conversations, "closed")).to be_empty
    end

    it "does not announce the same thread again on the next message" do
      conversation
      write
      before_second = turbo_broadcasts_to(hotel, :conversations, "all").size

      write(body: "Still there?")

      expect(turbo_broadcasts_to(hotel, :conversations, "all").size).to eq(before_second)
    end
  end

  describe "when who is holding the thread changes" do
    it "refreshes the row and the counts on a handover" do
      conversation
      user = create(:user, account: hotel.account)

      conversation.hand_to_human!(user: user)

      expect(inbox_payloads).to include(HotelPortal::Inbox::ListItem.dom_id_for(conversation))
      expect(inbox_payloads).to include("conversation-count-awaiting_staff")
    end

    it "refreshes the row when the thread is closed" do
      conversation

      conversation.close!

      expect(inbox_payloads).to include(HotelPortal::Inbox::ListItem.dom_id_for(conversation))
    end

    # An inbox that pushed on every touch would push on last_message_at, which
    # the row already learned about from the message that set it.
    it "stays quiet when nothing the list shows has changed" do
      conversation
      ActionCable.server.pubsub.clear

      conversation.update!(last_message_at: 1.minute.from_now)

      expect(turbo_broadcasts_to(hotel, :conversations)).to be_empty
    end
  end

  # Each thread's row is its own, but the tab counts belong to the hotel, so a
  # sweep closing many at once sends them once at the end rather than running a
  # full count query per thread to send the same correction over and over.
  describe "while many threads are being closed at once" do
    it "still pushes each row" do
      conversation
      ActionCable.server.pubsub.clear

      Conversation.deferring_inbox_counts { conversation.close! }

      expect(inbox_payloads).to include(HotelPortal::Inbox::ListItem.dom_id_for(conversation))
    end

    it "holds the counts back" do
      conversation
      ActionCable.server.pubsub.clear

      Conversation.deferring_inbox_counts { conversation.close! }

      expect(inbox_payloads).not_to include("conversation-count-")
    end

    it "sends them again once the sweep is over" do
      conversation
      Conversation.deferring_inbox_counts { conversation.close! }
      ActionCable.server.pubsub.clear

      Conversation.broadcast_counts_to_inbox(hotel)

      expect(inbox_payloads).to include("conversation-count-open")
    end

    it "puts the counts back even when the sweep blows up" do
      expect { Conversation.deferring_inbox_counts { raise "boom" } }.to raise_error("boom")

      conversation
      ActionCable.server.pubsub.clear
      conversation.close!

      expect(inbox_payloads).to include("conversation-count-open")
    end
  end
end
