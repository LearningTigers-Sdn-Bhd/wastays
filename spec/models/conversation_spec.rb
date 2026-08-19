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
end
