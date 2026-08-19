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

  # Both sides of the thread hear about a message from the model, so a writer
  # added later cannot forget to announce itself.
  describe "broadcasting" do
    it "pushes a guest message to the page the guest is looking at" do
      create(:prospect_message, prospect: prospect, conversation: conversation, body: "Any parking?")
      payloads = turbo_broadcasts_to(conversation, :guest)

      expect(payloads.join).to include("Any parking?")
      expect(payloads.join).to include(PublicUI::Chat::Log::DEFAULT_ID)
    end

    it "clears the empty-state line out of the way of the first message" do
      create(:prospect_message, prospect: prospect, conversation: conversation)
      payloads = turbo_broadcasts_to(conversation, :guest)

      expect(payloads.first).to include(%(action="remove"))
      expect(payloads.first).to include("#{PublicUI::Chat::Log::DEFAULT_ID}-empty")
    end

    it "pushes the same message to the inbox as well" do
      create(:prospect_message, prospect: prospect, conversation: conversation, body: "Any parking?")
      payloads = turbo_broadcasts_to(conversation, :staff)

      expect(payloads.join).to include("Any parking?")
      expect(payloads.join).to include(ActionView::RecordIdentifier.dom_id(conversation, :messages))
    end

    # The guest reads "You", the desk reads "Guest" -- which is the whole reason
    # there are two streams rather than one.
    it "renders each side in its own words" do
      create(:prospect_message, prospect: prospect, conversation: conversation, direction: "inbound")

      guest_side = turbo_broadcasts_to(conversation, :guest).join
      staff_side = turbo_broadcasts_to(conversation, :staff).join

      expect(guest_side).to include("You")
      expect(staff_side).to include("Guest")
    end

    # The guest-side renderer reaches for a view helper to name the author, and
    # a broadcast renders outside a request -- so this is the case that proves
    # the helper is there when nobody asked for it.
    it "names the person who wrote a staff reply on the guest's side" do
      staff = create(:user, account: hotel.account, name: "Farah Idris")
      create(:prospect_message,
             prospect: prospect,
             conversation: conversation,
             direction: "outbound",
             sender_role: "staff",
             sender_user: staff,
             body: "Yes, we have parking.")

      expect(turbo_broadcasts_to(conversation, :guest).join).to include("Farah Idris")
    end

    it "stays quiet for a message with no thread yet" do
      expect {
        create(:prospect_message, prospect: prospect, conversation: nil)
      }.not_to raise_error
    end
  end
end
