# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::PostStaffReply do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account, name: "Farah Idris") }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }

  def reply(body, on: conversation)
    described_class.new(conversation: on, user: user, body: body).call
  end

  it "files the reply against the thread and its author" do
    result = reply("We have parking, RM10 a night.")

    expect(result).to be_success
    expect(result.message.body).to eq("We have parking, RM10 a night.")
    expect(result.message.sender_role).to eq("staff")
    expect(result.message.sender_user).to eq(user)
    expect(result.message.direction).to eq("outbound")
  end

  # The decision the whole phase turns on: answering is taking the thread, so
  # the bot can never talk over someone who has already replied.
  it "takes the conversation over by the act of replying" do
    reply("We have parking.")

    expect(conversation.reload).to be_human
    expect(conversation.assigned_user).to eq(user)
  end

  it "announces the person before their first words, not after" do
    reply("We have parking.")

    roles = conversation.messages.reload.map(&:sender_role)
    expect(roles).to eq(%w[system staff])
  end

  it "does not announce anybody again on the second reply" do
    reply("First")
    reply("Second")

    expect(conversation.messages.reload.map(&:sender_role)).to eq(%w[system staff staff])
  end

  it "refuses an empty reply" do
    result = reply("   ")

    expect(result).not_to be_success
    expect(result.error).to include("Type a message")
    expect(conversation.messages.reload).to be_empty
  end

  it "refuses a reply longer than the limit" do
    result = reply("a" * (described_class::MAX_MESSAGE_LENGTH + 1))

    expect(result).not_to be_success
    expect(conversation.messages.reload).to be_empty
  end

  it "refuses to reply into a closed thread" do
    conversation.close!

    result = reply("Are you still there?")

    expect(result).not_to be_success
    expect(result.error).to include("closed")
  end

  describe "a WhatsApp thread" do
    let(:guest) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
    let(:whatsapp) { create(:conversation, hotel: hotel, prospect: guest, channel: "whatsapp") }

    it "accepts a reply once a relay is connected to carry it" do
      create(:webhook_endpoint, hotel: hotel, event_types: [ Concierge::DeliverStaffReply::EVENT ])

      result = reply("We have parking.", on: whatsapp)

      expect(result).to be_success
      expect(whatsapp.messages.reload.map(&:body)).to include("We have parking.")
    end

    # A reply nobody can deliver is worse than no reply box: staff believe they
    # have answered.
    it "refuses a reply with nothing to carry it, and says which thing is missing" do
      result = reply("We have parking.", on: whatsapp)

      expect(result).not_to be_success
      expect(result.error).to include("No WhatsApp relay")
      expect(whatsapp.messages.reload).to be_empty
    end

    describe "past WhatsApp's 24-hour window" do
      let!(:relay) do
        create(:webhook_endpoint, hotel: hotel, event_types: [ Concierge::DeliverStaffReply::EVENT ])
      end

      before { whatsapp.update!(last_guest_message_at: Conversation::REPLY_WINDOW.ago - 1.minute) }

      it "refuses the reply and says the guest has to write first" do
        result = reply("Sorry for the wait -- yes, we have parking.", on: whatsapp)

        expect(result).not_to be_success
        expect(result.error).to include("24 hours")
        expect(whatsapp.messages.reload).to be_empty
      end

      # The worst half of the old bug, and the reason the refusal has to come
      # before the transaction: replying took the thread, so a reply nobody
      # could deliver also silenced the bot that could still have answered.
      it "leaves the bot holding the thread" do
        reply("Sorry for the wait.", on: whatsapp)

        expect(whatsapp.reload).not_to be_human
        expect(whatsapp.assigned_user).to be_nil
      end
    end
  end
end
