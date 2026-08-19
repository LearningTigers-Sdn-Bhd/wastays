require "rails_helper"

RSpec.describe Conversation, type: :model do
  let(:hotel) { create(:hotel) }

  describe "validations" do
    it "accepts the default web/bot/open shape" do
      expect(build(:conversation, hotel: hotel)).to be_valid
    end

    it "rejects an unknown channel, mode or status" do
      expect(build(:conversation, hotel: hotel, channel: "carrier_pigeon")).not_to be_valid
      expect(build(:conversation, hotel: hotel, mode: "robot")).not_to be_valid
      expect(build(:conversation, hotel: hotel, status: "maybe")).not_to be_valid
    end
  end

  describe "one open thread per person per channel" do
    let(:prospect) { create(:prospect, hotel: hotel) }

    it "refuses a second open conversation on the same channel" do
      create(:conversation, hotel: hotel, prospect: prospect, channel: "web")

      expect {
        create(:conversation, hotel: hotel, prospect: prospect, channel: "web")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same person an open thread on a different channel" do
      create(:conversation, hotel: hotel, prospect: prospect, channel: "web")

      expect {
        create(:conversation, hotel: hotel, prospect: prospect, channel: "whatsapp")
      }.not_to raise_error
    end

    it "allows a fresh conversation once the previous one is closed" do
      create(:conversation, :closed, hotel: hotel, prospect: prospect, channel: "web")

      expect {
        create(:conversation, hotel: hotel, prospect: prospect, channel: "web")
      }.not_to raise_error
    end
  end

  describe "handover" do
    let(:conversation) { create(:conversation, hotel: hotel) }
    let(:user) { create(:user) }

    it "stops the bot and assigns an owner in one move" do
      conversation.hand_to_human!(user: user)

      expect(conversation).to be_human
      expect(conversation.assigned_user).to eq(user)
    end

    it "releases the thread back to the bot" do
      conversation.hand_to_human!(user: user)
      conversation.return_to_bot!

      expect(conversation).to be_bot
      expect(conversation.assigned_user).to be_nil
    end
  end

  describe "scopes" do
    it "surfaces only open threads waiting on a human" do
      waiting = create(:conversation, hotel: hotel, mode: "human")
      create(:conversation, hotel: hotel, mode: "bot")
      create(:conversation, :closed, hotel: hotel, mode: "human")

      expect(described_class.awaiting_staff).to contain_exactly(waiting)
    end
  end

  describe "where a reply can reach the guest" do
    it "accepts the channel the hotel owns the page for" do
      expect(build(:conversation, channel: "web")).to be_replies_reach_guest
    end

    it "refuses a channel with no outbound route yet" do
      expect(build(:conversation, channel: "whatsapp")).not_to be_replies_reach_guest
    end
  end

  describe "reopening" do
    let(:prospect) { create(:prospect, hotel: hotel) }

    it "clears the closing timestamp rather than leaving a contradiction" do
      conversation = create(:conversation, hotel: hotel, prospect: prospect)
      conversation.close!

      conversation.reopen!

      expect(conversation).to be_open
      expect(conversation.closed_at).to be_nil
    end
  end

  describe "what the guest is told about who is answering" do
    let(:prospect) { create(:prospect, hotel: hotel) }
    let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }

    it "invites a question while the assistant is answering and able to" do
      allow(hotel).to receive(:ai_concierge_ready?).and_return(true)

      expect(conversation.guest_status[:text]).to eq(Conversation::BOT_STATUS)
    end

    it "points at the front desk when there is no assistant" do
      expect(conversation.guest_status[:text]).to eq(Conversation::FRONT_DESK_STATUS)
    end

    it "names the person holding the thread" do
      user = create(:user, account: hotel.account, name: "Farah Idris")
      conversation.hand_to_human!(user: user)

      expect(conversation.guest_status[:text]).to include("Farah Idris")
      expect(conversation.guest_status[:tone]).to eq(:accent)
    end

    it "says a person has been sent for while the assistant carries on" do
      conversation.request_human!

      expect(conversation.guest_status[:text]).to eq(Conversation::HUMAN_REQUESTED_STATUS)
      expect(conversation.guest_status[:tone]).to eq(:accent)
    end

    # A visitor who has not written yet has no thread to ask, but the bar still
    # has a line to fill.
    it "answers for a hotel with no thread at all" do
      expect(described_class.guest_status_for(hotel)[:text]).to eq(Conversation::FRONT_DESK_STATUS)
    end

    # The guest's page is already open when staff take the thread, so the line
    # under the hotel's name has to change under them.
    it "pushes the new answer down the guest's stream the moment mode changes" do
      user = create(:user, account: hotel.account, name: "Farah Idris")

      conversation.hand_to_human!(user: user)

      expect(turbo_broadcasts_to(conversation, :guest).join).to include("Farah Idris")
    end

    it "pushes the new line down the stream when the guest asks for a person" do
      conversation.request_human!

      expect(turbo_broadcasts_to(conversation, :guest).join).to include(Conversation::HUMAN_REQUESTED_STATUS)
    end

    it "stays quiet when something other than mode changes" do
      conversation.update!(last_message_at: Time.current)

      expect(turbo_broadcasts_to(conversation, :guest)).to be_empty
    end
  end
end
