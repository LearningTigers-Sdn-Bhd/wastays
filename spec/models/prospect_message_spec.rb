require "rails_helper"

RSpec.describe ProspectMessage, type: :model do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }

  describe "sender_role" do
    it "derives the author from the direction when a caller omits it" do
      expect(create(:prospect_message, prospect: prospect, direction: "inbound").sender_role).to eq("guest")
      expect(create(:prospect_message, prospect: prospect, direction: "outbound").sender_role).to eq("bot")
      expect(create(:prospect_message, prospect: prospect, direction: "system").sender_role).to eq("system")
    end

    it "keeps an explicit staff role rather than assuming the bot wrote it" do
      user = create(:user)
      message = create(:prospect_message,
                       prospect: prospect,
                       direction: "outbound",
                       sender_role: "staff",
                       sender_user: user)

      expect(message.sender_role).to eq("staff")
      expect(message).to be_from_staff
      expect(message.sender_user).to eq(user)
    end

    it "rejects a role outside the known set" do
      expect(build(:prospect_message, prospect: prospect, sender_role: "manager")).not_to be_valid
    end
  end

  describe "touching the conversation" do
    it "moves the thread's last_message_at forward" do
      travel_to Time.current.change(usec: 0) do
        message = create(:prospect_message, prospect: prospect, conversation: conversation)

        expect(conversation.reload.last_message_at).to eq(message.sent_at)
      end
    end

    it "records a guest reply separately from a bot reply" do
      travel_to Time.current.change(usec: 0) do
        guest_message = create(:prospect_message, prospect: prospect, conversation: conversation, direction: "inbound")
        conversation.reload
        expect(conversation.last_guest_message_at).to eq(guest_message.sent_at)

        create(:prospect_message,
               prospect: prospect,
               conversation: conversation,
               direction: "outbound",
               sent_at: 1.hour.from_now)

        conversation.reload
        expect(conversation.last_message_at).to be > conversation.last_guest_message_at
      end
    end

    it "does not blow up for a message with no thread yet" do
      expect { create(:prospect_message, prospect: prospect, conversation: nil) }.not_to raise_error
    end
  end

  describe "unread" do
    it "counts only messages nobody has read" do
      create(:prospect_message, prospect: prospect, conversation: conversation)
      create(:prospect_message, prospect: prospect, conversation: conversation, read_at: Time.current)

      expect(conversation.unread_count).to eq(1)
    end
  end
end
